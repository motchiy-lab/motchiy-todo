package main

import (
	"encoding/json"
	"strings"
	"testing"
	"time"

	"go.mongodb.org/mongo-driver/bson/primitive"
)

func TestNormalizeEmail(t *testing.T) {
	tests := []struct {
		name  string
		input string
		want  string
	}{
		{name: "trims and lowercases", input: "  User.Name@Example.COM  ", want: "user.name@example.com"},
		{name: "rejects missing domain", input: "user@example", want: ""},
		{name: "rejects whitespace", input: "user name@example.com", want: ""},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			if got := normalizeEmail(test.input); got != test.want {
				t.Fatalf("normalizeEmail(%q) = %q, want %q", test.input, got, test.want)
			}
		})
	}
}

func TestValidateTask(t *testing.T) {
	valid := map[string]any{
		"id":          "task-1",
		"title":       "Test task",
		"description": "Test description",
		"isCompleted": false,
		"hasDueDate":  true,
		"dueDate":     "2026-11-23T10:36:02.494+09:00",
	}
	if err := validateTask(valid); err != nil {
		t.Fatalf("validateTask(valid) returned error: %v", err)
	}

	invalid := map[string]any{
		"id":      "task-1",
		"title":   "Test task",
		"unknown": true,
	}
	if err := validateTask(invalid); err == nil {
		t.Fatal("validateTask(invalid) returned nil")
	}
}

func TestDecodeSettings(t *testing.T) {
	settings, err := decodeSettings(strings.NewReader(`{
		"themeColorIndex": 2,
		"themeModeIndex": 1,
		"enableTabAnimations": true
	}`))
	if err != nil {
		t.Fatalf("decodeSettings(valid) returned error: %v", err)
	}
	colorIndex, ok := settings["themeColorIndex"].(json.Number)
	if !ok {
		t.Fatalf("themeColorIndex type = %T, want json.Number", settings["themeColorIndex"])
	}
	value, err := colorIndex.Int64()
	if err != nil || value != 2 {
		t.Fatalf("themeColorIndex = %q, want 2", colorIndex)
	}

	for _, body := range []string{
		`{"themeColorIndex":6}`,
		`{"themeModeIndex":1.5}`,
		`{"enableTabAnimations":"yes"}`,
		`{"unknown":true}`,
	} {
		if _, err := decodeSettings(strings.NewReader(body)); err == nil {
			t.Fatalf("decodeSettings(%q) returned nil", body)
		}
	}
}

func TestFixedWindowLimiter(t *testing.T) {
	limiter := newFixedWindowLimiter()

	if !limiter.allow("test", 2, time.Minute) {
		t.Fatal("first request was denied")
	}
	if !limiter.allow("test", 2, time.Minute) {
		t.Fatal("second request was denied")
	}
	if limiter.allow("test", 2, time.Minute) {
		t.Fatal("third request was allowed")
	}
	if !limiter.allow("other", 2, time.Minute) {
		t.Fatal("different key was denied")
	}
}

func TestAccessTokenRoundTrip(t *testing.T) {
	secret := []byte("01234567890123456789012345678901")
	userID := "123e4567-e89b-42d3-a456-426614174000"
	sessionID := primitive.NewObjectID()

	token, err := createAccessToken(userID, sessionID, secret)
	if err != nil {
		t.Fatalf("createAccessToken returned error: %v", err)
	}
	session, err := parseAccessToken(token, secret)
	if err != nil {
		t.Fatalf("parseAccessToken returned error: %v", err)
	}
	if session.UserID != userID {
		t.Fatalf("UserID = %q, want %q", session.UserID, userID)
	}
	if session.SessionID != sessionID {
		t.Fatalf("SessionID = %q, want %q", session.SessionID, sessionID)
	}

	if _, err := parseAccessToken(token, []byte("wrong-secret-wrong-secret-wrongsecret")); err == nil {
		t.Fatal("token parsed with the wrong secret")
	}
}

func TestVerificationCode(t *testing.T) {
	code, err := newVerificationCode()
	if err != nil {
		t.Fatalf("newVerificationCode returned error: %v", err)
	}
	if len(code) != 6 {
		t.Fatalf("verification code length = %d, want 6", len(code))
	}

	secret := []byte("01234567890123456789012345678901")
	hash := hashVerificationCode(code, secret)
	if !verificationCodeMatches(code, hash, secret) {
		t.Fatal("valid verification code did not match")
	}
	if verificationCodeMatches("incorrect", hash, secret) {
		t.Fatal("incorrect verification code matched")
	}
}

func TestDatabaseName(t *testing.T) {
	tests := []struct {
		uri  string
		want string
	}{
		{uri: "mongodb://127.0.0.1:27017/motchiy_todo", want: "motchiy_todo"},
		{uri: "mongodb://localhost:27017/", want: "motchiy_todo"},
	}

	for _, test := range tests {
		if got := databaseName(test.uri); got != test.want {
			t.Fatalf("databaseName(%q) = %q, want %q", test.uri, got, test.want)
		}
	}
}
