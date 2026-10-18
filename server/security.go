package main

import (
	"crypto/hmac"
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"encoding/hex"
	"errors"
	"net"
	"strings"
	"sync"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/golang-jwt/jwt/v5"
	"go.mongodb.org/mongo-driver/bson/primitive"
	"golang.org/x/crypto/scrypt"
)

const (
	accessTokenLifetime  = 15 * time.Minute
	refreshTokenLifetime = 30 * 24 * time.Hour
	tokenIssuer          = "motchiy-todo-api"
	tokenAudience        = "motchiy-todo-app"
)

type tokenClaims struct {
	SessionID string `json:"sid"`
	jwt.RegisteredClaims
}

type authSession struct {
	UserID    primitive.ObjectID
	SessionID primitive.ObjectID
}

type fixedWindowLimiter struct {
	mu      sync.Mutex
	entries map[string]rateEntry
}

type rateEntry struct {
	count int
	until time.Time
}

func newFixedWindowLimiter() *fixedWindowLimiter {
	return &fixedWindowLimiter{entries: make(map[string]rateEntry)}
}

func (l *fixedWindowLimiter) allow(key string, limit int, window time.Duration) bool {
	now := time.Now()
	l.mu.Lock()
	defer l.mu.Unlock()
	if len(l.entries) > 4096 {
		for existing, entry := range l.entries {
			if !entry.until.After(now) {
				delete(l.entries, existing)
			}
		}
	}
	if _, exists := l.entries[key]; !exists && len(l.entries) >= 4096 {
		return false
	}
	entry := l.entries[key]
	if !entry.until.After(now) {
		entry = rateEntry{until: now.Add(window)}
	}
	entry.count++
	l.entries[key] = entry
	return entry.count <= limit
}

func clientRateLimitKey(c *gin.Context) string {
	if forwarded := c.GetHeader("CF-Connecting-IP"); forwarded != "" {
		if ip := net.ParseIP(strings.TrimSpace(forwarded)); ip != nil {
			return ip.String()
		}
	}
	host, _, err := net.SplitHostPort(c.Request.RemoteAddr)
	if err == nil {
		return host
	}
	return c.Request.RemoteAddr
}

func hashPassword(password string) (string, error) {
	salt := make([]byte, 16)
	if _, err := rand.Read(salt); err != nil {
		return "", err
	}
	key, err := scrypt.Key([]byte(password), salt, 1<<15, 8, 1, 64)
	if err != nil {
		return "", err
	}
	return "scrypt$" + hex.EncodeToString(salt) + "$" + hex.EncodeToString(key), nil
}

func verifyPassword(password, encoded string) bool {
	parts := strings.Split(encoded, "$")
	if len(parts) != 3 || parts[0] != "scrypt" {
		return false
	}
	salt, err := hex.DecodeString(parts[1])
	if err != nil || len(salt) != 16 {
		return false
	}
	expected, err := hex.DecodeString(parts[2])
	if err != nil || len(expected) != 64 {
		return false
	}
	actual, err := scrypt.Key([]byte(password), salt, 1<<15, 8, 1, len(expected))
	return err == nil && hmac.Equal(expected, actual)
}

func newRefreshToken() (string, error) {
	value := make([]byte, 48)
	if _, err := rand.Read(value); err != nil {
		return "", err
	}
	return base64.RawURLEncoding.EncodeToString(value), nil
}

func hashToken(value string) string {
	hash := sha256.Sum256([]byte(value))
	return hex.EncodeToString(hash[:])
}

func createAccessToken(userID, sessionID primitive.ObjectID, secret []byte) (string, error) {
	now := time.Now().UTC()
	claims := tokenClaims{
		SessionID: sessionID.Hex(),
		RegisteredClaims: jwt.RegisteredClaims{
			Issuer:    tokenIssuer,
			Subject:   userID.Hex(),
			Audience:  jwt.ClaimStrings{tokenAudience},
			IssuedAt:  jwt.NewNumericDate(now),
			ExpiresAt: jwt.NewNumericDate(now.Add(accessTokenLifetime)),
		},
	}
	return jwt.NewWithClaims(jwt.SigningMethodHS256, claims).SignedString(secret)
}

func parseAccessToken(value string, secret []byte) (authSession, error) {
	claims := &tokenClaims{}
	token, err := jwt.ParseWithClaims(value, claims, func(token *jwt.Token) (any, error) {
		if token.Method != jwt.SigningMethodHS256 {
			return nil, errors.New("unexpected token signing algorithm")
		}
		return secret, nil
	}, jwt.WithIssuer(tokenIssuer), jwt.WithAudience(tokenAudience),
		jwt.WithExpirationRequired(), jwt.WithValidMethods([]string{jwt.SigningMethodHS256.Alg()}))
	if err != nil || token == nil || !token.Valid {
		return authSession{}, errors.New("invalid access token")
	}
	userID, err := primitive.ObjectIDFromHex(claims.Subject)
	if err != nil {
		return authSession{}, errors.New("invalid user identifier in access token")
	}
	sessionID, err := primitive.ObjectIDFromHex(claims.SessionID)
	if err != nil {
		return authSession{}, errors.New("invalid session identifier in access token")
	}
	return authSession{UserID: userID, SessionID: sessionID}, nil
}
