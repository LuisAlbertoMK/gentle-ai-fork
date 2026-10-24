package engram

import (
	"os"
	"path/filepath"
	"testing"

	"github.com/gentleman-programming/gentle-ai/v4/internal/components/filemerge"
	"github.com/gentleman-programming/gentle-ai/v4/internal/model"
)

func TestExistingNativeEngramCommand(t *testing.T) {
	raw := []byte(`{"mcp":{"engram":{"command":["stale"]},"servers":{"engram":{"type":"local","command":["/custom/engram","mcp"],"disabled":true}}}}`)
	got, ok := existingMergedEngramCommand(raw, model.AgentOpenCode)
	if !ok || got != "/custom/engram" {
		t.Fatalf("command=(%q,%v)", got, ok)
	}
}

func TestNativeEngramOverlayPreservesUserSettings(t *testing.T) {
	path := filepath.Join(t.TempDir(), "opencode.json")
	raw := []byte(`{"mcp":{"engram":{"type":"local","command":["stale"]},"servers":{"engram":{"type":"local","command":["/custom/engram","mcp"],"disabled":true,"environment":{"CUSTOM":"kept"}},"other":{"type":"remote","url":"https://example.invalid"}}}}`)
	if err := os.WriteFile(path, raw, 0600); err != nil {
		t.Fatal(err)
	}
	overlay, err := nativeOpenCodeEngramOverlay(path, engramOverlayJSON(model.AgentOpenCode, "/custom/engram"))
	if err != nil {
		t.Fatal(err)
	}
	if _, err := mergeJSONFile(path, overlay); err != nil {
		t.Fatal(err)
	}
	data, _ := os.ReadFile(path)
	root, err := filemerge.UnmarshalJSONObject(data)
	if err != nil {
		t.Fatal(err)
	}
	mcp := root["mcp"].(map[string]any)
	servers := mcp["servers"].(map[string]any)
	entry := servers["engram"].(map[string]any)
	if entry["disabled"] != true || entry["environment"].(map[string]any)["CUSTOM"] != "kept" || servers["other"] == nil {
		t.Fatalf("user native fields lost: %#v", mcp)
	}
	if got := mcp["engram"].(map[string]any)["command"].([]any)[0]; got != "stale" {
		t.Fatalf("unrelated legacy server modified: %v", got)
	}
}

// TestReadPersistedStdioCommandsFindsNativeOpenCodeEntry reproduces issue #5680:
// an OpenCode 2.x host persists Engram in the native mcp.servers shape, so the
// doctor's persisted-command reader must not report "no persisted MCP
// configuration found" for a correctly wired host.
func TestReadPersistedStdioCommandsFindsNativeOpenCodeEntry(t *testing.T) {
	home := t.TempDir()
	dir := filepath.Join(home, ".config", "opencode")
	if err := os.MkdirAll(dir, 0o755); err != nil {
		t.Fatal(err)
	}
	settings := filepath.Join(dir, "opencode.jsonc")
	content := "// native OpenCode 2.x wiring\n{\"mcp\":{\"servers\":{\"engram\":{\"type\":\"local\",\"command\":[\"/custom/engram\",\"mcp\",\"--tools=agent\"]}}}}\n"
	if err := os.WriteFile(settings, []byte(content), 0o600); err != nil {
		t.Fatal(err)
	}

	commands, err := ReadPersistedStdioCommands(home, []string{string(model.AgentOpenCode)})
	if err != nil {
		t.Fatalf("ReadPersistedStdioCommands error = %v", err)
	}
	if len(commands) != 1 {
		t.Fatalf("commands = %#v, want the native mcp.servers.engram entry", commands)
	}
	if commands[0].Command != "/custom/engram" || len(commands[0].Args) != 2 || commands[0].Args[0] != "mcp" {
		t.Fatalf("command = %#v, want /custom/engram mcp --tools=agent", commands[0])
	}
	if commands[0].Source != settings {
		t.Fatalf("source = %q, want %q", commands[0].Source, settings)
	}
}

// TestReadPersistedStdioCommandsKeepsLegacyOpenCodeEntry pins the 1.x shape so
// the native-shape preference cannot drop a host that never migrated.
func TestReadPersistedStdioCommandsKeepsLegacyOpenCodeEntry(t *testing.T) {
	home := t.TempDir()
	dir := filepath.Join(home, ".config", "opencode")
	if err := os.MkdirAll(dir, 0o755); err != nil {
		t.Fatal(err)
	}
	content := `{"mcp":{"engram":{"type":"local","command":["/legacy/engram","mcp"]}}}`
	if err := os.WriteFile(filepath.Join(dir, "opencode.json"), []byte(content), 0o600); err != nil {
		t.Fatal(err)
	}

	commands, err := ReadPersistedStdioCommands(home, []string{string(model.AgentOpenCode)})
	if err != nil {
		t.Fatalf("ReadPersistedStdioCommands error = %v", err)
	}
	if len(commands) != 1 || commands[0].Command != "/legacy/engram" {
		t.Fatalf("commands = %#v, want the legacy mcp.engram entry", commands)
	}
}
