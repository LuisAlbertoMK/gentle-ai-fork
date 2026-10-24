package filemerge

import (
	"fmt"
	"strings"
	"testing"
)

// buildJSONCSettings renders a settings-shaped JSONC document with the given
// number of top-level keys, mirroring the agent/tool entries OpenCode settings
// accumulate in real installations.
func buildJSONCSettings(keys int) []byte {
	var b strings.Builder
	b.WriteString("{\n")
	b.WriteString("  // managed by gentle-ai\n")
	for i := 0; i < keys; i++ {
		if i > 0 {
			b.WriteString(",\n")
		}
		fmt.Fprintf(&b, "  \"agent-%d\": {\"model\": \"lmstudio/qwen\", \"variant\": \"high\", \"tools\": {\"write\": true, \"bash\": true}}", i)
	}
	b.WriteString("\n}\n")
	return []byte(b.String())
}

// buildSettingsOverlay renders the values a writer would merge, touching the
// first `touched` keys of the base document.
func buildSettingsOverlay(touched int) []byte {
	var b strings.Builder
	b.WriteString("{")
	for i := 0; i < touched; i++ {
		if i > 0 {
			b.WriteString(",")
		}
		fmt.Fprintf(&b, "\"agent-%d\": {\"model\": \"lmstudio/qwen2\"}", i)
	}
	b.WriteString("}")
	return []byte(b.String())
}

// BenchmarkMergeOpenCodeJSONCObjects measures the settings write path across
// document sizes and touch counts. The per-key JSONC checks rescan the whole
// document, so a superlinear result here would mean every sync write pays it.
func BenchmarkMergeOpenCodeJSONCObjects(b *testing.B) {
	cases := []struct {
		name          string
		keys, touched int
	}{
		{"small/8keys/touch1", 8, 1},
		{"medium/600keys/touch10", 600, 10},
		{"large/4800keys/touch10", 4800, 10},
		{"medium/600keys/touchAll", 600, 600},
	}
	for _, tc := range cases {
		base := buildJSONCSettings(tc.keys)
		overlay := buildSettingsOverlay(tc.touched)
		b.Run(tc.name, func(b *testing.B) {
			b.ReportAllocs()
			b.SetBytes(int64(len(base)))
			for i := 0; i < b.N; i++ {
				if _, err := MergeOpenCodeJSONCObjects(base, overlay); err != nil {
					b.Fatalf("merge: %v", err)
				}
			}
		})
	}
}
