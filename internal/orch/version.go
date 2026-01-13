package orch

// Version is the orchd binary version. It can be overridden at build time
// using -ldflags, e.g.:
//
//   go build -ldflags "-X 'github.com/oorrwullie/orchd/internal/orch.Version=v0.1.0'" ...
//
// By default it's "dev".
var Version = "dev"
