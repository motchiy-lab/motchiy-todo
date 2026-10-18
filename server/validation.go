package main

import (
	"bytes"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"math"
	"net/mail"
	"regexp"
	"strings"
	"time"
	"unicode/utf8"
)

const maxRequestBody = 1 << 20

var emailPattern = regexp.MustCompile(`^[^\s@]+@[^\s@]+\.[^\s@]+$`)

var allowedTaskFields = map[string]bool{
	"id": true, "title": true, "description": true, "isCompleted": true,
	"startDate": true, "dueDate": true, "completedAt": true, "hasDueDate": true,
}

type apiError struct {
	Status  int    `json:"-"`
	Message string `json:"message"`
}

func (e *apiError) Error() string { return e.Message }

func badRequest(message string) error {
	return &apiError{Status: 400, Message: message}
}

func normalizeEmail(value string) string {
	value = strings.ToLower(strings.TrimSpace(value))
	if len(value) > 254 || !emailPattern.MatchString(value) {
		return ""
	}
	address, err := mail.ParseAddress(value)
	if err != nil || address.Address != value {
		return ""
	}
	return value
}

func decodeJSON(reader io.Reader, destination any) error {
	body, err := io.ReadAll(io.LimitReader(reader, maxRequestBody+1))
	if err != nil {
		return badRequest("リクエスト本文を読み込めません。")
	}
	if len(body) > maxRequestBody {
		return badRequest("リクエスト本文が大きすぎます。")
	}
	decoder := json.NewDecoder(bytes.NewReader(body))
	decoder.UseNumber()
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(destination); err != nil {
		return badRequest("JSONの形式または項目が正しくありません。")
	}
	var extra any
	if err := decoder.Decode(&extra); !errors.Is(err, io.EOF) {
		return badRequest("JSON本文に余分なデータがあります。")
	}
	return nil
}

func decodeTaskList(reader io.Reader) ([]map[string]any, error) {
	var request struct {
		Tasks []map[string]any `json:"tasks"`
	}
	if err := decodeJSON(reader, &request); err != nil {
		return nil, err
	}
	if request.Tasks == nil || len(request.Tasks) > 5000 {
		return nil, badRequest("タスク一覧の形式が正しくありません。")
	}
	for _, task := range request.Tasks {
		if err := validateTask(task); err != nil {
			return nil, err
		}
	}
	return request.Tasks, nil
}

func validateTask(task map[string]any) error {
	if task == nil {
		return badRequest("タスクの形式が正しくありません。")
	}
	for key := range task {
		if !allowedTaskFields[key] {
			return badRequest(fmt.Sprintf("タスクに未対応の項目があります: %s", key))
		}
	}
	id, idOK := task["id"].(string)
	title, titleOK := task["title"].(string)
	description, descriptionOK := task["description"].(string)
	if !descriptionOK {
		description = ""
		if _, exists := task["description"]; exists {
			return badRequest("タスクの説明は文字列で指定してください。")
		}
	}
	if !idOK || id == "" || len(id) > 128 || !utf8.ValidString(id) ||
		!titleOK || len(title) > 500 || !utf8.ValidString(title) ||
		len(description) > 10000 || !utf8.ValidString(description) {
		return badRequest("タスクのID、タイトル、または説明が不正です。")
	}
	for _, key := range []string{"isCompleted", "hasDueDate"} {
		if value, exists := task[key]; exists {
			if _, ok := value.(bool); !ok {
				return badRequest("タスクの状態項目は真偽値で指定してください。")
			}
		}
	}
	for _, key := range []string{"startDate", "dueDate", "completedAt"} {
		value, exists := task[key]
		if !exists || value == nil {
			continue
		}
		text, ok := value.(string)
		if !ok {
			return badRequest("タスクの日付はISO 8601形式で指定してください。")
		}
		if _, err := time.Parse(time.RFC3339Nano, text); err != nil {
			return badRequest("タスクの日付はISO 8601形式で指定してください。")
		}
	}
	return nil
}

func decodeSettings(reader io.Reader) (map[string]any, error) {
	var settings map[string]any
	if err := decodeJSON(reader, &settings); err != nil {
		return nil, err
	}
	if settings == nil {
		return nil, badRequest("設定の形式が正しくありません。")
	}
	for key, raw := range settings {
		switch key {
		case "themeColorIndex":
			number, ok := jsonInteger(raw)
			if !ok || number < 0 || number > 5 {
				return nil, badRequest("themeColorIndexは0〜5の整数で指定してください。")
			}
		case "themeModeIndex":
			number, ok := jsonInteger(raw)
			if !ok || number < 0 || number > 2 {
				return nil, badRequest("themeModeIndexは0〜2の整数で指定してください。")
			}
		case "enableTabAnimations":
			if _, ok := raw.(bool); !ok {
				return nil, badRequest("enableTabAnimationsは真偽値で指定してください。")
			}
		default:
			return nil, badRequest("設定に未対応の項目があります。")
		}
	}
	return settings, nil
}

func jsonInteger(value any) (int64, bool) {
	number, ok := value.(json.Number)
	if !ok {
		return 0, false
	}
	integer, err := number.Int64()
	return integer, err == nil && math.Abs(float64(integer)) <= 1<<53
}
