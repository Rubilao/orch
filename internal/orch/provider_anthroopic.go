package orch

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"os"
	"time"
)

type anthropicProvider struct {
	httpClient *http.Client
}

func init() {
	registerProvider("anthropic", &anthropicProvider{
		httpClient: &http.Client{Timeout: 30 * time.Second},
	})
}

type anthropicMessageRequest struct {
	Model       string                    `json:"model"`
	MaxTokens   int                       `json:"max_tokens"`
	Temperature float64                   `json:"temperature,omitempty"`
	Messages    []anthropicMessageContent `json:"messages"`
}

type anthropicMessageContent struct {
	Role    string `json:"role"`
	Content string `json:"content"`
}

type anthropicMessageResponse struct {
	Content []struct {
		Text string `json:"text"`
	} `json:"content"`
	Error *struct {
		Message string `json:"message"`
	} `json:"error,omitempty"`
}

func (p *anthropicProvider) Call(ctx context.Context, cfg ModelConfig, prompt, code string) (string, error) {
	apiKey := cfg.APIKey
	if apiKey == "" {
		apiKey = os.Getenv("ANTHROPIC_API_KEY")
	}
	if apiKey == "" {
		return "", errors.New("missing Anthropic API key")
	}

	content := prompt
	if code != "" {
		content = content + "\n\n```code\n" + code + "\n```"
	}

	maxTokens := cfg.MaxTokens
	if maxTokens <= 0 {
		maxTokens = 2048
	}

	body := anthropicMessageRequest{
		Model:     cfg.Model,
		MaxTokens: maxTokens,
		Messages: []anthropicMessageContent{
			{Role: "user", Content: content},
		},
	}
	if cfg.Temperature > 0 {
		body.Temperature = cfg.Temperature
	}

	data, err := json.Marshal(body)
	if err != nil {
		return "", err
	}

	endpoint := cfg.Endpoint
	if endpoint == "" {
		endpoint = "https://api.anthropic.com/v1/messages"
	}

	req, err := http.NewRequestWithContext(ctx, http.MethodPost, endpoint, bytes.NewReader(data))
	if err != nil {
		return "", err
	}

	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("x-api-key", apiKey)
	req.Header.Set("anthropic-version", "2023-06-01")

	resp, err := p.httpClient.Do(req)
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()

	var decoded anthropicMessageResponse
	if err := json.NewDecoder(resp.Body).Decode(&decoded); err != nil {
		return "", err
	}

	if decoded.Error != nil {
		return "", fmt.Errorf("anthropic error: %s", decoded.Error.Message)
	}
	if len(decoded.Content) == 0 {
		return "", errors.New("anthropic: no content in response")
	}

	return decoded.Content[0].Text, nil
}
