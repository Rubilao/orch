package orch

import "context"

type Provider interface {
	Call(ctx context.Context, cfg ModelConfig, prompt, code string) (string, error)
}

var providerRegistry = map[string]Provider{}

// in init() of provider files we'll register them
func registerProvider(name string, p Provider) {
	providerRegistry[name] = p
}

func getProvider(name string) Provider {
	return providerRegistry[name]
}
