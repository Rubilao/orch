// internal/orch/orchestrator_test.go
package orch

import (
	"bufio"
	"bytes"
	"context"
	"encoding/json"
	"strings"
	"testing"
	"time"
)

// helper to build a context with timeout for tests
func testCtx(t *testing.T) context.Context {
	t.Helper()
	ctx, _ := context.WithTimeout(context.Background(), 2*time.Second)
	return ctx
}

func TestRun_WithNoModels_ReturnsEmptyResults(t *testing.T) {
	ctx := testCtx(t)

	req := Request{
		Prompt:         "explain this",
		Code:           "fmt.Println(\"hello\")",
		Models:         nil, // no models
		TimeoutSeconds: 1,
	}

	resp := Run(ctx, req)

	if resp.Results == nil {
		// treat nil as empty, but we still want to assert no entries
		return
	}
	if len(resp.Results) != 0 {
		t.Fatalf("expected 0 results, got %d", len(resp.Results))
	}
}

func TestRunStream_WithNoModels_EmitsDoneEvent(t *testing.T) {
	ctx := testCtx(t)

	req := Request{
		Prompt:         "explain this",
		Code:           "fmt.Println(\"hello\")",
		Models:         nil, // no models
		TimeoutSeconds: 1,
		Stream:         true,
	}

	var buf bytes.Buffer
	if err := RunStream(ctx, req, &buf); err != nil {
		t.Fatalf("RunStream returned error: %v", err)
	}

	type event struct {
		Event string `json:"event"`
		Name  string `json:"name,omitempty"`
	}

	var (
		seenResult bool
		seenDone   bool
	)

	scanner := bufio.NewScanner(bytes.NewReader(buf.Bytes()))
	for scanner.Scan() {
		line := strings.TrimSpace(scanner.Text())
		if line == "" {
			continue
		}

		var ev event
		if err := json.Unmarshal([]byte(line), &ev); err != nil {
			t.Fatalf("failed to unmarshal event JSON %q: %v", line, err)
		}

		switch ev.Event {
		case "result":
			seenResult = true
		case "done":
			seenDone = true
		}
	}

	if err := scanner.Err(); err != nil {
		t.Fatalf("scanner error: %v", err)
	}

	if seenResult {
		t.Fatalf("expected no result events when Models is empty")
	}
	if !seenDone {
		t.Fatalf("expected a done event, but none was seen")
	}
}
