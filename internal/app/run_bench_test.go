package app

import (
	"io"
	"testing"
)

// BenchmarkRunArgsVersion measures the in-process cost of the cheapest command
// the CLI can answer. Anything above a few microseconds points at eager init on
// the dispatch path every invocation pays for.
func BenchmarkRunArgsVersion(b *testing.B) {
	b.ReportAllocs()
	for i := 0; i < b.N; i++ {
		if err := RunArgs([]string{"--version"}, io.Discard); err != nil {
			b.Fatalf("run: %v", err)
		}
	}
}

// BenchmarkRunArgsHelp measures help rendering, the largest static output the
// CLI can produce without touching the filesystem.
func BenchmarkRunArgsHelp(b *testing.B) {
	b.ReportAllocs()
	for i := 0; i < b.N; i++ {
		if err := RunArgs([]string{"--help"}, io.Discard); err != nil {
			b.Fatalf("run: %v", err)
		}
	}
}
