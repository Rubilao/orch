package orch

import (
	"context"
	"time"
)

type ModelConfig struct {
	Name     string `json:"name"`
	Provider string `json:"provider"`
	Model    string `json:"model"`

	// Optional:
	APIKey   string `json:"api_key,omitempty"`
	Endpoint string `json:"endpoint,omitempty"`

	Temperature float64 `json:"temperature,omitempty"`
	MaxTokens   int     `json:"max_tokens,omitempty"`
}

type Request struct {
	Prompt         string        `json:"prompt"`
	Code           string        `json:"code"`
	Models         []ModelConfig `json:"models"`
	TimeoutSeconds int           `json:"timeout_seconds,omitempty"`
	Stream         bool          `json:"stream,omitempty"` // NEW: enable streaming events
}

type ModelResult struct {
	Name     string `json:"name"`
	Provider string `json:"provider"`
	Text     string `json:"text,omitempty"`
	Error    string `json:"error,omitempty"`
}

type Response struct {
	Results []ModelResult `json:"results"`
}

// WithTimeout is a small helper so we don't pull in extra deps.
func WithTimeout(d time.Duration) (context.Context, context.CancelFunc) {
	return context.WithTimeout(context.Background(), d)
}
