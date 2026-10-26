package main

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"os"
	"strings"
	"time"
)

type verificationMailer interface {
	sendVerificationCode(context.Context, string, string) error
}

type resendMailer struct {
	apiKey string
	from   string
	client *http.Client
}

func newResendMailerFromEnv() (resendMailer, error) {
	apiKey := strings.TrimSpace(os.Getenv("RESEND_API_KEY"))
	from := strings.TrimSpace(os.Getenv("EMAIL_FROM"))
	if apiKey == "" || from == "" {
		return resendMailer{}, errors.New("RESEND_API_KEY and EMAIL_FROM are required")
	}
	return resendMailer{
		apiKey: apiKey,
		from:   from,
		client: &http.Client{Timeout: 15 * time.Second},
	}, nil
}

func (m resendMailer) sendVerificationCode(ctx context.Context, email, code string) error {
	payload := struct {
		From    string   `json:"from"`
		To      []string `json:"to"`
		Subject string   `json:"subject"`
		Text    string   `json:"text"`
	}{
		From:    m.from,
		To:      []string{email},
		Subject: "Motchiy ToDo 認証コード",
		Text:    fmt.Sprintf("認証コードは %s です。有効期限は15分です。", code),
	}
	body, err := json.Marshal(payload)
	if err != nil {
		return fmt.Errorf("encode verification email: %w", err)
	}
	request, err := http.NewRequestWithContext(ctx, http.MethodPost, "https://api.resend.com/emails", bytes.NewReader(body))
	if err != nil {
		return fmt.Errorf("create Resend request: %w", err)
	}
	request.Header.Set("Authorization", "Bearer "+m.apiKey)
	request.Header.Set("Content-Type", "application/json")

	response, err := m.client.Do(request)
	if err != nil {
		return fmt.Errorf("send verification email through Resend: %w", err)
	}
	defer response.Body.Close()
	_, _ = io.Copy(io.Discard, io.LimitReader(response.Body, 1<<20))
	if response.StatusCode < http.StatusOK || response.StatusCode >= http.StatusMultipleChoices {
		return fmt.Errorf("Resend rejected verification email with HTTP %d", response.StatusCode)
	}
	return nil
}
