package uninstall

import (
	"encoding/json"
	"os"
	"path/filepath"
	"runtime"
	"slices"
	"strings"
	"testing"

	opencodeagent "github.com/gentleman-programming/gentle-ai/v4/internal/agents/opencode"
	"github.com/gentleman-programming/gentle-ai/v4/internal/model"
	"github.com/gentleman-programming/gentle-ai/v4/internal/state"
)

func releasedSDDSkill(t *testing.T) string {
	t.Helper()
	data, err := os.ReadFile(filepath.Join("..", "legacyassets", "testdata", "v3.7.0", "skill-sdd-init.md"))
	if err != nil {
		t.Fatal(err)
	}
	return string(data)
}

// Retired SDD files belong to no removable component: only an uninstall that
// removes the whole runtime retires them.
func TestPartialComponentUninstallLeavesRetiredSDDFiles(t *testing.T) {
	home := t.TempDir()
	t.Setenv("HOME", home)
	skill := filepath.Join(home, ".claude", "skills", "sdd-init", "SKILL.md")
	writeBatchFile(t, skill, releasedSDDSkill(t))
	svc, err := NewService(home, t.TempDir(), "dev")
	if err != nil {
		t.Fatal(err)
	}
	svc.snapshotter = stubSnapshotter{}
	if _, err := svc.PartialUninstall([]model.AgentID{model.AgentClaudeCode}, []model.ComponentID{model.ComponentTheme}); err != nil {
		t.Fatal(err)
	}
	if got, err := os.ReadFile(skill); err != nil || string(got) != releasedSDDSkill(t) {
		t.Fatalf("theme-only uninstall changed the retired SDD skill: %v", err)
	}
}

// A retirement that fails keeps the runtime in state.json, names it in the
// manual actions, and still reports what it already removed.
func TestRetiredSDDFailureKeepsRuntimeInState(t *testing.T) {
	if runtime.GOOS == "windows" || os.Geteuid() == 0 {
		t.Skip("needs POSIX directory permissions enforced")
	}
	home := t.TempDir()
	t.Setenv("HOME", home)
	skill := filepath.Join(home, ".claude", "skills", "sdd-init", "SKILL.md")
	writeBatchFile(t, skill, releasedSDDSkill(t))
	command, err := os.ReadFile(filepath.Join("..", "legacyassets", "testdata", "v2.0.0", "claude-sdd-init.md"))
	if err != nil {
		t.Fatal(err)
	}
	commands := filepath.Join(home, ".claude", "commands")
	writeBatchFile(t, filepath.Join(commands, "sdd-init.md"), string(command))
	if err := os.Chmod(commands, 0o555); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = os.Chmod(commands, 0o755) })
	if err := state.Write(home, state.InstallState{InstalledAgents: []string{string(model.AgentClaudeCode)}}); err != nil {
		t.Fatal(err)
	}
	svc, err := NewService(home, t.TempDir(), "dev")
	if err != nil {
		t.Fatal(err)
	}
	svc.snapshotter = stubSnapshotter{}
	result, err := svc.PartialUninstall([]model.AgentID{model.AgentClaudeCode}, nil)
	if err == nil {
		t.Fatal("PartialUninstall() succeeded although a retired SDD command could not be removed")
	}
	if !slices.Contains(result.FailedAgents, model.AgentClaudeCode) || slices.Contains(result.AgentsRemovedFromState, model.AgentClaudeCode) {
		t.Fatalf("failed = %v, removed from state = %v, want claude-code kept in state", result.FailedAgents, result.AgentsRemovedFromState)
	}
	if !slices.Contains(result.RemovedFiles, skill) {
		t.Fatalf("removed files = %v, want the skill retired before the failure", result.RemovedFiles)
	}
	recorded, err := state.Read(home)
	if err != nil || !slices.Contains(recorded.InstalledAgents, string(model.AgentClaudeCode)) {
		t.Fatalf("state = %v, %v, want claude-code still installed", recorded.InstalledAgents, err)
	}
}

func releasedSDDPrompt(t *testing.T, name string) string {
	t.Helper()
	data, err := os.ReadFile(filepath.Join("..", "legacyassets", "testdata", "v3.7.0", name))
	if err != nil {
		t.Fatal(err)
	}
	return string(data)
}

// The full uninstall retires the shared SDD prompts, but an entry settings
// retirement preserves keeps loading its {file:} substitution: retiring that
// file leaves the runtime unable to load the configuration, the same failure
// sync now avoids (#5623).
func TestRetiredSDDUninstallKeepsPromptPreservedEntryReferences(t *testing.T) {
	for _, tc := range []struct {
		name     string
		preserve bool
	}{
		{name: "preserved entry references the prompt", preserve: true},
		{name: "no surviving reference retires it", preserve: false},
	} {
		t.Run(tc.name, func(t *testing.T) {
			home := t.TempDir()
			config := opencodeagent.ConfigPath(home)
			settings := filepath.Join(config, "opencode.json")
			prompt := filepath.Join(config, "prompts", "sdd", "sdd-apply.md")
			released := releasedSDDPrompt(t, "opencode-prompt-sdd-apply.md")
			writeBatchFile(t, prompt, released)
			if tc.preserve {
				custom := map[string]any{
					"mode":        "subagent",
					"hidden":      true,
					"description": "Execute implementation tasks",
					"model":       "github-copilot/claude-opus-4.6",
					"options":     map[string]any{"temperature": json.Number("0.2")},
					"prompt":      "{file:" + filepath.ToSlash(prompt) + "}",
				}
				data, err := json.Marshal(map[string]any{"agent": map[string]any{"sdd-apply": custom}})
				if err != nil {
					t.Fatal(err)
				}
				writeBatchFile(t, settings, string(data))
			}

			svc, err := NewService(home, t.TempDir(), "dev")
			if err != nil {
				t.Fatal(err)
			}
			adapter, ok := svc.registry.Get(model.AgentOpenCode)
			if !ok {
				t.Fatal("OpenCode adapter is not registered")
			}
			op, _, ok := svc.retiredSDDOperation(adapter)
			if !ok {
				t.Fatal("retired SDD operation is not scheduled for OpenCode")
			}
			if _, _, err := op.apply(""); err != nil {
				t.Fatal(err)
			}
			var result Result
			op.report(&result)

			if !tc.preserve {
				if _, err := os.Stat(prompt); !os.IsNotExist(err) {
					t.Fatalf("unreferenced prompt stat error = %v, want it retired", err)
				}
				return
			}
			got, err := os.ReadFile(prompt)
			if err != nil {
				t.Fatalf("referenced prompt was retired: %v", err)
			}
			if string(got) != released {
				t.Fatal("referenced prompt changed")
			}
			kept, err := os.ReadFile(settings)
			if err != nil || !strings.Contains(string(kept), "sdd-apply") {
				t.Fatalf("preserved settings entry was removed: %s (%v)", kept, err)
			}
			if !slices.ContainsFunc(result.ManualActions, func(action string) bool {
				return strings.Contains(action, prompt) && strings.Contains(action, "referenced")
			}) {
				t.Fatalf("manual actions = %v, want a notice for the referenced prompt", result.ManualActions)
			}
		})
	}
}
