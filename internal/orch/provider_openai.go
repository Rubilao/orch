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

type openAIProvider struct {
	httpClient *http.Client
}

func init() {
	registerProvider("openai", &openAIProvider{
		httpClient: &http.Client{Timeout: 30 * time.Second},
	})
}

type openAIChatRequest struct {
	Model       string              `json:"model"`
	Messages    []openAIChatMessage `json:"messages"`
	Temperature float64             `json:"temperature,omitempty"`
	MaxTokens   int                 `json:"max_tokens,omitempty"`
}

type openAIChatMessage struct {
	Role    string `json:"role"`
	Content string `json:"content"`
}

type openAIChatResponse struct {
	Choices []struct {
		Message openAIChatMessage `json:"message"`
	} `json:"choices"`
	Error *struct {
		Message string `json:"message"`
	} `json:"error,omitempty"`
}

func (p *openAIProvider) Call(ctx context.Context, cfg ModelConfig, prompt, code string) (string, error) {
	apiKey := cfg.APIKey
	if apiKey == "" {
		apiKey = os.Getenv("OPENAI_API_KEY")
	}
	if apiKey == "" {
		return "", errors.New("missing OpenAI API key")
	}

	content := prompt
	if code != "" {
		content = content + "\n\n```code\n" + code + "\n```"
	}

	body := openAIChatRequest{
		Model:    cfg.Model,
		Messages: []openAIChatMessage{{Role: "user", Content: content}},
	}
	if cfg.Temperature > 0 {
		body.Temperature = cfg.Temperature
	}
	if cfg.MaxTokens > 0 {
		body.MaxTokens = cfg.MaxTokens
	}

	data, err := json.Marshal(body)
	if err != nil {
		return "", err
	}

	endpoint := cfg.Endpoint
	if endpoint == "" {
		endpoint = "https://api.openai.com/v1/chat/completions"
	}

	req, err := http.NewRequestWithContext(ctx, http.MethodPost, endpoint, bytes.NewReader(data))
	if err != nil {
		return "", err
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", "Bearer "+apiKey)

	resp, err := p.httpClient.Do(req)
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()

	var decoded openAIChatResponse
	if err := json.NewDecoder(resp.Body).Decode(&decoded); err != nil {
		return "", err
	}

	if decoded.Error != nil {
		return "", fmt.Errorf("openai error: %s", decoded.Error.Message)
	}

	if len(decoded.Choices) == 0 {
		return "", errors.New("openai: no choices in response")
	}

	return decoded.Choices[0].Message.Content, nil
}
