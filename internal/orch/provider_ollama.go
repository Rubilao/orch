package orch

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"time"
)

type ollamaProvider struct {
	httpClient *http.Client
}

func init() {
	registerProvider("ollama", &ollamaProvider{
		httpClient: &http.Client{Timeout: 30 * time.Second},
	})
}

type ollamaChatRequest struct {
	Model    string                 `json:"model"`
	Messages []ollamaChatMessage    `json:"messages"`
	Stream   bool                   `json:"stream"`
	Options  map[string]interface{} `json:"options,omitempty"`
}

type ollamaChatMessage struct {
	Role    string `json:"role"`
	Content string `json:"content"`
}

type ollamaChatResponse struct {
	Message struct {
		Role    string `json:"role"`
		Content string `json:"content"`
	} `json:"message"`
	Error string `json:"error,omitempty"`
}

func (p *ollamaProvider) Call(ctx context.Context, cfg ModelConfig, prompt, code string) (string, error) {
	content := prompt
	if code != "" {
		content = content + "\n\n```code\n" + code + "\n```"
	}

	body := ollamaChatRequest{
		Model: cfg.Model,
		Messages: []ollamaChatMessage{
			{Role: "user", Content: content},
		},
		Stream: false,
	}

	data, err := json.Marshal(body)
	if err != nil {
		return "", err
	}

	endpoint := cfg.Endpoint
	if endpoint == "" {
		endpoint = "http://127.0.0.1:11434/api/chat"
	}

	req, err := http.NewRequestWithContext(ctx, http.MethodPost, endpoint, bytes.NewReader(data))
	if err != nil {
		return "", err
	}
	req.Header.Set("Content-Type", "application/json")

	resp, err := p.httpClient.Do(req)
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()

	var decoded ollamaChatResponse
	if err := json.NewDecoder(resp.Body).Decode(&decoded); err != nil {
		return "", err
	}
	if decoded.Error != "" {
		return "", errors.New("ollama error: " + decoded.Error)
	}
	return decoded.Message.Content, nil
}
