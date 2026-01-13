# Makefile for Orch (orchd daemon)

# ----- Configuration -------------------------------------------------

GO           ?= go
BINARY_NAME   = orchd
CMD_DIR       = ./cmd/orchd

PREFIX      ?= /usr/local
BINDIR       = $(PREFIX)/bin

INSTALL     ?= install

# Version for release builds
VERSION     ?= v0.1.0

# Module path used for -ldflags -X. CHANGE THIS to your actual module path.
# Example: github.com/oorrwullie/orch
MODULE_PATH ?= github.com/yourname/orchd

# ----- Targets -------------------------------------------------------

.PHONY: all build install uninstall clean test release

all: build

build:
	@echo "==> Building $(BINARY_NAME) from $(CMD_DIR) (dev build, Version=$(VERSION) not baked)"
	@mkdir -p bin
	$(GO) build -o bin/$(BINARY_NAME) $(CMD_DIR)

install: build
	@echo "==> Installing $(BINARY_NAME) to $(BINDIR)"
	@mkdir -p $(BINDIR)
	$(INSTALL) -m 0755 bin/$(BINARY_NAME) $(BINDIR)/$(BINARY_NAME)
	@echo "==> Installed $(BINDIR)/$(BINARY_NAME)"

uninstall:
	@echo "==> Removing $(BINDIR)/$(BINARY_NAME) (if present)"
	@rm -f $(BINDIR)/$(BINARY_NAME)

clean:
	@echo "==> Cleaning build artifacts"
	@rm -rf bin dist

test:
	@echo "==> Running Go tests"
	$(GO) test ./...

# Release build:
# - Strips symbols (-s -w)
# - Bakes VERSION into orch.Version via -X
# - Outputs to dist/orchd
release:
	@echo "==> Building release $(BINARY_NAME) (Version=$(VERSION))"
	@mkdir -p dist
	$(GO) build \
		-ldflags "-s -w -X '$(MODULE_PATH)/internal/orch.Version=$(VERSION)'" \
		-o dist/$(BINARY_NAME) $(CMD_DIR)
	@echo "==> Release binary written to dist/$(BINARY_NAME)"

