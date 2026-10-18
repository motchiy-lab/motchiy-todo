package main

import (
	"context"
	"errors"
	"fmt"
	"log"
	"net/http"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
	"go.mongodb.org/mongo-driver/bson"
	"go.mongodb.org/mongo-driver/bson/primitive"
	"go.mongodb.org/mongo-driver/mongo"
	"go.mongodb.org/mongo-driver/mongo/options"
)

type api struct {
	db        *mongo.Database
	jwtSecret []byte
	limiter   *fixedWindowLimiter
}

type account struct {
	ID           primitive.ObjectID `bson:"_id,omitempty"`
	Email        string             `bson:"email"`
	DisplayName  string             `bson:"displayName"`
	PasswordHash string             `bson:"passwordHash"`
}

type session struct {
	ID               primitive.ObjectID `bson:"_id,omitempty"`
	UserID           primitive.ObjectID `bson:"userId"`
	RefreshTokenHash string             `bson:"refreshTokenHash"`
	ExpiresAt        time.Time          `bson:"expiresAt"`
	RevokedAt        *time.Time         `bson:"revokedAt"`
}

type taskList struct {
	UserID primitive.ObjectID `bson:"userId"`
	Tasks  []map[string]any   `bson:"tasks"`
}

type userSettings struct {
	UserID              primitive.ObjectID `bson:"userId"`
	ThemeColorIndex     int                `bson:"themeColorIndex"`
	ThemeModeIndex      int                `bson:"themeModeIndex"`
	EnableTabAnimations bool               `bson:"enableTabAnimations"`
}

type tokenResponse struct {
	AccessToken  string        `json:"accessToken"`
	RefreshToken string        `json:"refreshToken"`
	ExpiresIn    int64         `json:"expiresIn"`
	User         publicAccount `json:"user"`
}

type publicAccount struct {
	ID          string `json:"id"`
	Email       string `json:"email"`
	DisplayName string `json:"displayName"`
	PhotoURL    any    `json:"photoUrl"`
}

type authCredentials struct {
	Email    string `json:"email"`
	Password string `json:"password"`
}

func newAPI(database *mongo.Database, secret []byte) (*api, error) {
	if database == nil {
		return nil, errors.New("MongoDB database is required")
	}
	if len(secret) < 32 {
		return nil, errors.New("JWT_SECRET must be at least 32 bytes")
	}
	return &api{
		db: database, jwtSecret: secret,
		limiter: newFixedWindowLimiter(),
	}, nil
}

func (a *api) ensureIndexes(ctx context.Context) error {
	indexes := []struct {
		collection string
		models     []mongo.IndexModel
	}{
		{"users", []mongo.IndexModel{
			{Keys: bson.D{{Key: "email", Value: 1}}, Options: options.Index().SetUnique(true)},
		}},
		{"sessions", []mongo.IndexModel{
			{Keys: bson.D{{Key: "refreshTokenHash", Value: 1}}, Options: options.Index().SetUnique(true)},
			{Keys: bson.D{{Key: "expiresAt", Value: 1}}, Options: options.Index().SetExpireAfterSeconds(0)},
			{Keys: bson.D{{Key: "userId", Value: 1}}},
		}},
		{"tasklists", []mongo.IndexModel{
			{Keys: bson.D{{Key: "userId", Value: 1}}, Options: options.Index().SetUnique(true)},
		}},
		{"usersettings", []mongo.IndexModel{
			{Keys: bson.D{{Key: "userId", Value: 1}}, Options: options.Index().SetUnique(true)},
		}},
	}
	for _, item := range indexes {
		if _, err := a.db.Collection(item.collection).Indexes().CreateMany(ctx, item.models); err != nil {
			return fmt.Errorf("create %s indexes: %w", item.collection, err)
		}
	}
	return nil
}

func (a *api) registerRoutes(router *gin.Engine) {
	group := router.Group("")
	group.GET("/health", a.health)
	group.POST("/auth/register", a.rateLimit("register"), a.register)
	group.POST("/auth/login", a.rateLimit("login"), a.login)
	group.POST("/auth/refresh", a.rateLimit("refresh"), a.refresh)

	protected := group.Group("/")
	protected.Use(a.authMiddleware())
	protected.POST("/auth/logout", a.logout)
	protected.GET("/tasks", a.getTasks)
	protected.PUT("/tasks", a.putTasks)
	protected.GET("/settings", a.getSettings)
	protected.PATCH("/settings", a.patchSettings)
}

func corsMiddleware(allowedOrigins []string) gin.HandlerFunc {
	allowed := make(map[string]struct{}, len(allowedOrigins))
	for _, origin := range allowedOrigins {
		if origin = strings.TrimSpace(origin); origin != "" {
			allowed[origin] = struct{}{}
		}
	}
	return func(c *gin.Context) {
		origin := c.GetHeader("Origin")
		if origin == "" {
			c.Next()
			return
		}
		if _, ok := allowed[origin]; !ok {
			writeError(c, http.StatusForbidden, "このオリジンからのアクセスは許可されていません。")
			c.Abort()
			return
		}
		c.Header("Access-Control-Allow-Origin", origin)
		c.Header("Vary", "Origin")
		if c.Request.Method == http.MethodOptions {
			c.Header("Access-Control-Allow-Methods", "GET, POST, PUT, PATCH, OPTIONS")
			c.Header("Access-Control-Allow-Headers", "Content-Type, Authorization")
			c.Status(http.StatusNoContent)
			c.Abort()
			return
		}
		c.Next()
	}
}

func (a *api) rateLimit(action string) gin.HandlerFunc {
	return func(c *gin.Context) {
		ipKey := action + ":ip:" + clientRateLimitKey(c)
		if !a.limiter.allow(ipKey, 30, 15*time.Minute) {
			writeError(c, http.StatusTooManyRequests, "リクエスト回数が上限を超えました。時間をおいて再度お試しください。")
			c.Abort()
			return
		}
		c.Next()
	}
}

func (a *api) health(c *gin.Context) {
	ctx, cancel := context.WithTimeout(c.Request.Context(), 3*time.Second)
	defer cancel()
	if err := a.db.Client().Ping(ctx, nil); err != nil {
		writeError(c, http.StatusServiceUnavailable, "データベースに接続できません。")
		return
	}
	c.JSON(http.StatusOK, gin.H{"status": "ok"})
}

func (a *api) register(c *gin.Context) {
	var request struct {
		Email       string `json:"email"`
		Password    string `json:"password"`
		DisplayName string `json:"displayName"`
	}
	if !bindJSON(c, &request) {
		return
	}
	email := normalizeEmail(request.Email)
	displayName := strings.TrimSpace(request.DisplayName)
	if email == "" || len([]byte(request.Password)) > 128 || len([]rune(request.Password)) < 12 ||
		displayName == "" || len([]rune(displayName)) > 80 {
		writeError(c, http.StatusBadRequest, "入力内容が正しくありません。")
		return
	}
	passwordHash, err := hashPassword(request.Password)
	if err != nil {
		writeServerError(c, err)
		return
	}
	user := account{
		Email: email, DisplayName: displayName, PasswordHash: passwordHash,
	}
	result, err := a.db.Collection("users").InsertOne(c.Request.Context(), user)
	if mongo.IsDuplicateKeyError(err) {
		writeError(c, http.StatusConflict, "このメールアドレスはすでに登録されています。")
		return
	}
	if err != nil {
		writeServerError(c, err)
		return
	}
	user.ID = result.InsertedID.(primitive.ObjectID)
	a.createSessionResponse(c, user)
}

func (a *api) login(c *gin.Context) {
	var request authCredentials
	if !bindJSON(c, &request) {
		return
	}
	email := normalizeEmail(request.Email)
	if email == "" || len([]byte(request.Password)) > 128 {
		writeError(c, http.StatusUnauthorized, "メールアドレスまたはパスワードが正しくありません。")
		return
	}
	if !a.limiter.allow("login:email:"+email, 10, 15*time.Minute) {
		writeError(c, http.StatusTooManyRequests, "ログイン試行回数が上限を超えました。")
		return
	}
	var user account
	err := a.db.Collection("users").FindOne(c.Request.Context(), bson.M{"email": email}).Decode(&user)
	if errors.Is(err, mongo.ErrNoDocuments) || (err == nil && !verifyPassword(request.Password, user.PasswordHash)) {
		writeError(c, http.StatusUnauthorized, "メールアドレスまたはパスワードが正しくありません。")
		return
	}
	if err != nil {
		writeServerError(c, err)
		return
	}
	a.createSessionResponse(c, user)
}

func (a *api) refresh(c *gin.Context) {
	var request struct {
		RefreshToken string `json:"refreshToken"`
	}
	if !bindJSON(c, &request) {
		return
	}
	if request.RefreshToken == "" || len(request.RefreshToken) > 256 {
		writeError(c, http.StatusUnauthorized, "リフレッシュトークンが無効です。")
		return
	}
	now := time.Now().UTC()
	var current session
	err := a.db.Collection("sessions").FindOne(
		c.Request.Context(),
		bson.M{
			"refreshTokenHash": hashToken(request.RefreshToken),
			"revokedAt":        nil,
			"expiresAt":        bson.M{"$gt": now},
		},
	).Decode(&current)
	if errors.Is(err, mongo.ErrNoDocuments) {
		writeError(c, http.StatusUnauthorized, "リフレッシュトークンが無効または期限切れです。")
		return
	}
	if err != nil {
		writeServerError(c, err)
		return
	}
	var user account
	err = a.db.Collection("users").FindOne(c.Request.Context(), bson.M{"_id": current.UserID}).Decode(&user)
	if errors.Is(err, mongo.ErrNoDocuments) {
		if _, revokeErr := a.db.Collection("sessions").UpdateOne(c.Request.Context(),
			bson.M{"_id": current.ID, "userId": current.UserID},
			bson.M{"$set": bson.M{"revokedAt": now}},
		); revokeErr != nil {
			writeServerError(c, revokeErr)
			return
		}
		writeError(c, http.StatusUnauthorized, "ユーザーが見つかりません。")
		return
	}
	if err != nil {
		writeServerError(c, err)
		return
	}
	nextRefreshToken, err := newRefreshToken()
	if err != nil {
		writeServerError(c, err)
		return
	}
	accessToken, err := createAccessToken(user.ID, current.ID, a.jwtSecret)
	if err != nil {
		writeServerError(c, err)
		return
	}
	result, err := a.db.Collection("sessions").UpdateOne(c.Request.Context(),
		bson.M{
			"_id": current.ID, "userId": current.UserID,
			"refreshTokenHash": hashToken(request.RefreshToken),
			"revokedAt":        nil, "expiresAt": bson.M{"$gt": now},
		},
		bson.M{"$set": bson.M{
			"refreshTokenHash": hashToken(nextRefreshToken),
			"expiresAt":        now.Add(refreshTokenLifetime),
		}},
	)
	if err != nil {
		writeServerError(c, err)
		return
	}
	if result.ModifiedCount != 1 {
		writeError(c, http.StatusUnauthorized, "リフレッシュトークンが無効または期限切れです。")
		return
	}
	c.JSON(http.StatusOK, tokenResponse{
		AccessToken: accessToken, RefreshToken: nextRefreshToken,
		ExpiresIn: int64(accessTokenLifetime.Seconds()), User: toPublicAccount(user),
	})
}

func (a *api) logout(c *gin.Context) {
	auth := authFromContext(c)
	now := time.Now().UTC()
	_, err := a.db.Collection("sessions").UpdateOne(c.Request.Context(), bson.M{
		"_id": auth.SessionID, "userId": auth.UserID, "revokedAt": nil,
	}, bson.M{"$set": bson.M{"revokedAt": now}})
	if err != nil {
		writeServerError(c, err)
		return
	}
	c.Status(http.StatusNoContent)
}

func (a *api) getTasks(c *gin.Context) {
	auth := authFromContext(c)
	var list taskList
	err := a.db.Collection("tasklists").FindOne(c.Request.Context(), bson.M{"userId": auth.UserID}).Decode(&list)
	if errors.Is(err, mongo.ErrNoDocuments) {
		c.JSON(http.StatusOK, gin.H{"tasks": []any{}})
		return
	}
	if err != nil {
		writeServerError(c, err)
		return
	}
	if list.Tasks == nil {
		list.Tasks = []map[string]any{}
	}
	c.JSON(http.StatusOK, gin.H{"tasks": list.Tasks})
}

func (a *api) putTasks(c *gin.Context) {
	tasks, err := decodeTaskList(c.Request.Body)
	if err != nil {
		writeAPIError(c, err)
		return
	}
	auth := authFromContext(c)
	_, err = a.db.Collection("tasklists").UpdateOne(c.Request.Context(),
		bson.M{"userId": auth.UserID},
		bson.M{"$set": bson.M{"tasks": tasks}},
		options.Update().SetUpsert(true),
	)
	if err != nil {
		writeServerError(c, err)
		return
	}
	c.Status(http.StatusNoContent)
}

func (a *api) getSettings(c *gin.Context) {
	auth := authFromContext(c)
	var settings userSettings
	err := a.db.Collection("usersettings").FindOne(c.Request.Context(), bson.M{"userId": auth.UserID}).Decode(&settings)
	if errors.Is(err, mongo.ErrNoDocuments) {
		c.JSON(http.StatusOK, gin.H{
			"themeColorIndex": 0, "themeModeIndex": 0, "enableTabAnimations": true,
		})
		return
	}
	if err != nil {
		writeServerError(c, err)
		return
	}
	c.JSON(http.StatusOK, gin.H{
		"themeColorIndex":     settings.ThemeColorIndex,
		"themeModeIndex":      settings.ThemeModeIndex,
		"enableTabAnimations": settings.EnableTabAnimations,
	})
}

func (a *api) patchSettings(c *gin.Context) {
	settings, err := decodeSettings(c.Request.Body)
	if err != nil {
		writeAPIError(c, err)
		return
	}
	updates := bson.M{}
	for key, value := range settings {
		switch number := value.(type) {
		case interface{ Int64() (int64, error) }:
			integer, _ := number.Int64()
			updates[key] = integer
		default:
			updates[key] = value
		}
	}
	if len(updates) == 0 {
		c.Status(http.StatusNoContent)
		return
	}
	defaults := bson.M{
		"themeColorIndex": 0, "themeModeIndex": 0, "enableTabAnimations": true,
	}
	for key := range updates {
		delete(defaults, key)
	}
	update := bson.M{"$set": updates}
	if len(defaults) > 0 {
		update["$setOnInsert"] = defaults
	}
	auth := authFromContext(c)
	_, err = a.db.Collection("usersettings").UpdateOne(c.Request.Context(),
		bson.M{"userId": auth.UserID}, update, options.Update().SetUpsert(true))
	if err != nil {
		writeServerError(c, err)
		return
	}
	c.Status(http.StatusNoContent)
}

func (a *api) authMiddleware() gin.HandlerFunc {
	return func(c *gin.Context) {
		authorization := c.GetHeader("Authorization")
		if !strings.HasPrefix(authorization, "Bearer ") {
			writeError(c, http.StatusUnauthorized, "ログインしてください。")
			c.Abort()
			return
		}
		auth, err := parseAccessToken(strings.TrimPrefix(authorization, "Bearer "), a.jwtSecret)
		if err != nil {
			writeError(c, http.StatusUnauthorized, "認証トークンが無効または期限切れです。")
			c.Abort()
			return
		}
		var current session
		err = a.db.Collection("sessions").FindOne(c.Request.Context(), bson.M{
			"_id": auth.SessionID, "userId": auth.UserID, "revokedAt": nil,
			"expiresAt": bson.M{"$gt": time.Now().UTC()},
		}).Decode(&current)
		if errors.Is(err, mongo.ErrNoDocuments) {
			writeError(c, http.StatusUnauthorized, "ログインの有効期限が切れました。")
			c.Abort()
			return
		}
		if err != nil {
			writeServerError(c, err)
			c.Abort()
			return
		}
		c.Set("auth", auth)
		c.Next()
	}
}

func authFromContext(c *gin.Context) authSession {
	value, ok := c.Get("auth")
	if !ok {
		panic("authenticated route is missing auth middleware")
	}
	auth, ok := value.(authSession)
	if !ok {
		panic("invalid authentication context")
	}
	return auth
}

func (a *api) createSessionResponse(c *gin.Context, user account) {
	refreshToken, err := newRefreshToken()
	if err != nil {
		writeServerError(c, err)
		return
	}
	current := session{
		UserID: user.ID, RefreshTokenHash: hashToken(refreshToken),
		ExpiresAt: time.Now().UTC().Add(refreshTokenLifetime),
	}
	result, err := a.db.Collection("sessions").InsertOne(c.Request.Context(), current)
	if err != nil {
		writeServerError(c, err)
		return
	}
	sessionID, ok := result.InsertedID.(primitive.ObjectID)
	if !ok {
		writeServerError(c, errors.New("MongoDB returned an invalid session ID"))
		return
	}
	accessToken, err := createAccessToken(user.ID, sessionID, a.jwtSecret)
	if err != nil {
		writeServerError(c, err)
		return
	}
	c.JSON(http.StatusOK, tokenResponse{
		AccessToken: accessToken, RefreshToken: refreshToken,
		ExpiresIn: int64(accessTokenLifetime.Seconds()), User: toPublicAccount(user),
	})
}

func toPublicAccount(user account) publicAccount {
	return publicAccount{
		ID: user.ID.Hex(), Email: user.Email, DisplayName: user.DisplayName, PhotoURL: nil,
	}
}

func bindJSON(c *gin.Context, destination any) bool {
	if err := decodeJSON(c.Request.Body, destination); err != nil {
		writeAPIError(c, err)
		return false
	}
	return true
}

func writeAPIError(c *gin.Context, err error) {
	var apiErr *apiError
	if errors.As(err, &apiErr) {
		writeError(c, apiErr.Status, apiErr.Message)
		return
	}
	writeServerError(c, err)
}

func writeError(c *gin.Context, status int, message string) {
	c.JSON(status, gin.H{"message": message})
}

func writeServerError(c *gin.Context, err error) {
	log.Printf("API request failed: %v", err)
	writeError(c, http.StatusInternalServerError, "サーバーでエラーが発生しました。")
}
