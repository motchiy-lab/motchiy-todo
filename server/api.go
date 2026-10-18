package main

import (
	"context"
	"errors"
	"fmt"
	"log"
	"net/http"
	"regexp"
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
	mailer    verificationMailer
	limiter   *fixedWindowLimiter
}

type account struct {
	ID                        primitive.ObjectID `bson:"_id,omitempty"`
	UserID                    string             `bson:"userId"`
	Email                     string             `bson:"email"`
	DisplayName               string             `bson:"displayName"`
	PasswordHash              string             `bson:"passwordHash"`
	EmailVerified             bool               `bson:"emailVerified"`
	VerificationCodeHash      string             `bson:"verificationCodeHash,omitempty"`
	VerificationCodeExpiresAt *time.Time         `bson:"verificationCodeExpiresAt,omitempty"`
	VerificationAttempts      int                `bson:"verificationAttempts"`
}

type session struct {
	ID               primitive.ObjectID `bson:"_id,omitempty"`
	UserID           string             `bson:"userId"`
	RefreshTokenHash string             `bson:"refreshTokenHash"`
	ExpiresAt        time.Time          `bson:"expiresAt"`
	RevokedAt        *time.Time         `bson:"revokedAt"`
}

type taskList struct {
	UserID string           `bson:"userId"`
	Tasks  []map[string]any `bson:"tasks"`
}

type userSettings struct {
	UserID              string `bson:"userId"`
	ThemeColorIndex     int    `bson:"themeColorIndex"`
	ThemeModeIndex      int    `bson:"themeModeIndex"`
	EnableTabAnimations bool   `bson:"enableTabAnimations"`
}

type tokenResponse struct {
	AccessToken  string        `json:"accessToken"`
	RefreshToken string        `json:"refreshToken"`
	ExpiresIn    int64         `json:"expiresIn"`
	User         publicAccount `json:"user"`
}

type publicAccount struct {
	ID            string `json:"id"`
	Email         string `json:"email"`
	DisplayName   string `json:"displayName"`
	PhotoURL      any    `json:"photoUrl"`
	EmailVerified bool   `json:"emailVerified"`
}

type authCredentials struct {
	Email    string `json:"email"`
	Password string `json:"password"`
}

const verificationLifetime = 15 * time.Minute

var verificationCodePattern = regexp.MustCompile(`^[0-9]{6}$`)

func newAPI(database *mongo.Database, secret []byte, emailer verificationMailer) (*api, error) {
	if database == nil {
		return nil, errors.New("MongoDB database is required")
	}
	if len(secret) < 32 {
		return nil, errors.New("JWT_SECRET must be at least 32 bytes")
	}
	if emailer == nil {
		return nil, errors.New("Resend verification email sender is required")
	}
	return &api{
		db: database, jwtSecret: secret, mailer: emailer,
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
			{Keys: bson.D{{Key: "userId", Value: 1}}, Options: options.Index().SetUnique(true)},
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
	group.POST("/auth/verification/resend", a.rateLimit("resend"), a.resendVerification)
	group.POST("/auth/verify-email", a.rateLimit("verify"), a.verifyEmail)
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
	if !a.limiter.allow("register:email:"+email, 5, 15*time.Minute) {
		writeError(c, http.StatusTooManyRequests, "このメールアドレスでの登録回数が上限を超えました。")
		return
	}
	userID, err := newUserID()
	if err != nil {
		writeServerError(c, err)
		return
	}
	passwordHash, err := hashPassword(request.Password)
	if err != nil {
		writeServerError(c, err)
		return
	}
	code, err := newVerificationCode()
	if err != nil {
		writeServerError(c, err)
		return
	}
	expiresAt := time.Now().UTC().Add(verificationLifetime)
	user := account{
		UserID: userID, Email: email, DisplayName: displayName, PasswordHash: passwordHash,
		EmailVerified: false, VerificationCodeHash: hashVerificationCode(code, a.jwtSecret),
		VerificationCodeExpiresAt: &expiresAt,
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
	var ok bool
	user.ID, ok = result.InsertedID.(primitive.ObjectID)
	if !ok {
		writeServerError(c, errors.New("MongoDB returned an invalid user ID"))
		return
	}
	if err := a.mailer.sendVerificationCode(c.Request.Context(), user.Email, code); err != nil {
		writeServerError(c, err)
		return
	}
	c.JSON(http.StatusAccepted, gin.H{"message": "確認コードをメールで送信しました。"})
}

func (a *api) resendVerification(c *gin.Context) {
	var request struct {
		Email string `json:"email"`
	}
	if !bindJSON(c, &request) {
		return
	}
	email := normalizeEmail(request.Email)
	if email != "" && !a.limiter.allow("resend:email:"+email, 5, 15*time.Minute) {
		writeError(c, http.StatusTooManyRequests, "確認コードの送信回数が上限を超えました。")
		return
	}
	if email != "" {
		code, err := newVerificationCode()
		if err != nil {
			writeServerError(c, err)
			return
		}
		expiresAt := time.Now().UTC().Add(verificationLifetime)
		result, err := a.db.Collection("users").UpdateOne(c.Request.Context(),
			bson.M{"email": email, "emailVerified": bson.M{"$ne": true}},
			bson.M{"$set": bson.M{
				"emailVerified": false, "verificationCodeHash": hashVerificationCode(code, a.jwtSecret),
				"verificationCodeExpiresAt": expiresAt, "verificationAttempts": 0,
			}},
		)
		if err != nil {
			writeServerError(c, err)
			return
		}
		if result.ModifiedCount == 1 {
			if err := a.mailer.sendVerificationCode(c.Request.Context(), email, code); err != nil {
				writeServerError(c, err)
				return
			}
		}
	}
	c.JSON(http.StatusAccepted, gin.H{"message": "アカウントが存在し、未認証の場合は確認コードを送信しました。"})
}

func (a *api) verifyEmail(c *gin.Context) {
	var request struct {
		Email string `json:"email"`
		Code  string `json:"code"`
	}
	if !bindJSON(c, &request) {
		return
	}
	email := normalizeEmail(request.Email)
	if email == "" || !verificationCodePattern.MatchString(request.Code) {
		writeError(c, http.StatusBadRequest, "メールアドレスまたは確認コードが正しくありません。")
		return
	}
	if !a.limiter.allow("verify:email:"+email, 10, 15*time.Minute) {
		writeError(c, http.StatusTooManyRequests, "確認コードの入力回数が上限を超えました。")
		return
	}
	ctx := c.Request.Context()
	var user account
	err := a.db.Collection("users").FindOneAndUpdate(
		ctx,
		bson.M{
			"email": email, "emailVerified": bson.M{"$ne": true},
			"verificationCodeExpiresAt": bson.M{"$gt": time.Now().UTC()},
			"verificationAttempts":      bson.M{"$lt": 5},
		},
		bson.M{"$inc": bson.M{"verificationAttempts": 1}},
		options.FindOneAndUpdate().SetReturnDocument(options.Before),
	).Decode(&user)
	if errors.Is(err, mongo.ErrNoDocuments) {
		writeError(c, http.StatusUnauthorized, "確認コードが無効か、有効期限が切れています。")
		return
	}
	if err != nil {
		writeServerError(c, err)
		return
	}
	if !verificationCodeMatches(request.Code, user.VerificationCodeHash, a.jwtSecret) {
		writeError(c, http.StatusUnauthorized, "確認コードが無効か、有効期限が切れています。")
		return
	}
	result, err := a.db.Collection("users").UpdateOne(ctx, bson.M{
		"_id": user.ID, "emailVerified": bson.M{"$ne": true},
		"verificationCodeHash":      user.VerificationCodeHash,
		"verificationCodeExpiresAt": bson.M{"$gt": time.Now().UTC()},
		"verificationAttempts":      bson.M{"$lte": 5},
	}, bson.M{
		"$set":   bson.M{"emailVerified": true, "verificationCodeHash": "", "verificationAttempts": 0},
		"$unset": bson.M{"verificationCodeExpiresAt": ""},
	})
	if err != nil {
		writeServerError(c, err)
		return
	}
	if result.ModifiedCount != 1 {
		writeError(c, http.StatusUnauthorized, "確認コードが無効か、有効期限が切れています。")
		return
	}
	user.EmailVerified = true
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
	if !user.EmailVerified {
		writeError(c, http.StatusForbidden, "メールアドレスの認証が完了していません。確認コードを入力してください。")
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
	err = a.db.Collection("users").FindOne(c.Request.Context(), bson.M{"userId": current.UserID}).Decode(&user)
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
	if !user.EmailVerified {
		_, revokeErr := a.db.Collection("sessions").UpdateOne(c.Request.Context(),
			bson.M{"_id": current.ID, "userId": current.UserID, "revokedAt": nil},
			bson.M{"$set": bson.M{"revokedAt": now}},
		)
		if revokeErr != nil {
			writeServerError(c, revokeErr)
			return
		}
		writeError(c, http.StatusForbidden, "メールアドレスの認証が完了していません。")
		return
	}
	nextRefreshToken, err := newRefreshToken()
	if err != nil {
		writeServerError(c, err)
		return
	}
	accessToken, err := createAccessToken(user.UserID, current.ID, a.jwtSecret)
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
		var user account
		err = a.db.Collection("users").FindOne(c.Request.Context(),
			bson.M{"userId": auth.UserID, "emailVerified": true},
		).Decode(&user)
		if errors.Is(err, mongo.ErrNoDocuments) {
			writeError(c, http.StatusUnauthorized, "メールアドレスの認証が完了していません。")
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
		UserID: user.UserID, RefreshTokenHash: hashToken(refreshToken),
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
	accessToken, err := createAccessToken(user.UserID, sessionID, a.jwtSecret)
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
		ID: user.UserID, Email: user.Email, DisplayName: user.DisplayName, PhotoURL: nil,
		EmailVerified: user.EmailVerified,
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
	if mongo.IsTimeout(err) || mongo.IsNetworkError(err) {
		writeError(c, http.StatusServiceUnavailable, "データベースに接続できません。MongoDBの起動と接続設定を確認してください。")
		return
	}
	writeError(c, http.StatusInternalServerError, "サーバーでエラーが発生しました。")
}
