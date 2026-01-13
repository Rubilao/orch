package orch

import (
	"context"
	"encoding/json"
	"io"
	"sync"
)

type Provider interface {
	Call(ctx context.Context, cfg ModelConfig, prompt, code string) (string, error)
}

var providerRegistry = map[string]Provider{}

func registerProvider(name string, p Provider) {
	providerRegistry[name] = p
}

func getProvider(name string) Provider {
	return providerRegistry[name]
}

// Non-streaming orchestration: returns a single Response.
func Run(ctx context.Context, req Request) Response {
	results := make([]ModelResult, len(req.Models))

	var wg sync.WaitGroup
	wg.Add(len(req.Models))

	for i, cfg := range req.Models {
		i, cfg := i, cfg
		go func() {
			defer wg.Done()

			res := ModelResult{
				Name:     cfg.Name,
				Provider: cfg.Provider,
			}

			p := getProvider(cfg.Provider)
			if p == nil {
				res.Error = "unknown provider: " + cfg.Provider
				results[i] = res
				return
			}

			text, err := p.Call(ctx, cfg, req.Prompt, req.Code)
			if err != nil {
				res.Error = err.Error()
			} else {
				res.Text = text
			}

			results[i] = res
		}()
	}

	wg.Wait()
	return Response{Results: results}
}

// Streaming events: one JSON object per line:
//   {"event":"result", ...} for each model
//   {"event":"done"} at the end.
type streamEvent struct {
	Event string `json:"event"`
	ModelResult
}

// RunStream executes all models concurrently and writes streaming
// JSON events to w. It returns when all events are written.
func RunStream(ctx context.Context, req Request, w io.Writer) error {
	resultsCh := make(chan ModelResult)

	var wg sync.WaitGroup
	wg.Add(len(req.Models))

	for _, cfg := range req.Models {
		cfg := cfg
		go func() {
			defer wg.Done()

			res := ModelResult{
				Name:     cfg.Name,
				Provider: cfg.Provider,
			}

			p := getProvider(cfg.Provider)
			if p == nil {
				res.Error = "unknown provider: " + cfg.Provider
			} else {
				text, err := p.Call(ctx, cfg, req.Prompt, req.Code)
				if err != nil {
					res.Error = err.Error()
				} else {
					res.Text = text
				}
			}

			select {
			case <-ctx.Done():
				// Stop sending if context cancelled
				return
			case resultsCh <- res:
			}
		}()
	}

	// Close resultsCh when all goroutines finish
	go func() {
		wg.Wait()
		close(resultsCh)
	}()

	enc := json.NewEncoder(w)

	// Write each result as it arrives
	for res := range resultsCh {
		ev := streamEvent{
			Event:       "result",
			ModelResult: res,
		}
		if err := enc.Encode(ev); err != nil {
			return err
		}
	}

	// Final "done" event
	if err := enc.Encode(struct {
		Event string `json:"event"`
	}{
		Event: "done",
	}); err != nil {
		return err
	}

	return nil
}
