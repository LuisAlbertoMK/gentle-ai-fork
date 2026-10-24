package cli

import (
	"testing"

	"github.com/gentleman-programming/gentle-ai/v4/internal/system"
)

// BenchmarkCheckDependenciesStepRun measures the dependency preflight the
// install pipeline runs before any mutation. It shells out to every detected
// tool's version command, so it is dominated by subprocess spawn cost.
func BenchmarkCheckDependenciesStepRun(b *testing.B) {
	step := checkDependenciesStep{
		id:      "prepare:check-dependencies",
		profile: system.PlatformProfile{OS: "windows", PackageManager: "winget", Supported: true},
	}
	b.ReportAllocs()
	for i := 0; i < b.N; i++ {
		if err := step.Run(); err != nil {
			b.Fatalf("run: %v", err)
		}
	}
}
