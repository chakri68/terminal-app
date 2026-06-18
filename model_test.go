package main

import (
	"strings"
	"testing"

	tea "github.com/charmbracelet/bubbletea"
)

// stripANSI removes color/style escape sequences so assertions can match the
// plain text content of a rendered view regardless of the active color profile.
func stripANSI(s string) string {
	var b strings.Builder
	inEsc := false
	for _, r := range s {
		switch {
		case r == '\x1b':
			inEsc = true
		case inEsc && r == 'm':
			inEsc = false
		case inEsc:
			// skip escape body
		default:
			b.WriteRune(r)
		}
	}
	return b.String()
}

func TestGuestView(t *testing.T) {
	m := newModel("alice", "xterm-256color", "standard", 80, 24, nil)
	if m.admin {
		t.Fatalf("alice should not be an admin")
	}

	out := stripANSI(m.View())
	for _, want := range []string{
		"Hey there, alice",
		"Something awesome is coming soon",
		"terminal.chakri.me",
		"press q to quit",
	} {
		if !strings.Contains(out, want) {
			t.Errorf("guest view missing %q\n---\n%s", want, out)
		}
	}
}

func TestAdminView(t *testing.T) {
	m := newModel("chakri", "xterm-256color", "standard", 80, 24, nil)
	if !m.admin {
		t.Fatalf("chakri should be an admin")
	}

	out := stripANSI(m.View())
	for _, want := range []string{
		"welcome back, chakri",
		"make deploy",
		"DEPLOY.md",
	} {
		if !strings.Contains(out, want) {
			t.Errorf("admin view missing %q\n---\n%s", want, out)
		}
	}
}

func TestIsAdmin(t *testing.T) {
	t.Setenv("ADMIN_USERS", "chakri, root")
	cases := map[string]bool{
		"chakri": true,
		"CHAKRI": true, // case-insensitive
		"root":   true, // trims whitespace in the list
		"alice":  false,
		"":       false,
	}
	for user, want := range cases {
		if got := isAdmin(user); got != want {
			t.Errorf("isAdmin(%q) = %v, want %v", user, got, want)
		}
	}
}

// TestUpdateTickAnimates verifies a tick advances the animation frame and keeps
// the loop going by issuing another command.
func TestUpdateTickAnimates(t *testing.T) {
	m := newModel("guest", "xterm-256color", "standard", 80, 24, nil)

	updated, cmd := m.Update(tickMsg{})
	if cmd == nil {
		t.Fatal("tick should reschedule another tick command")
	}
	if got := updated.(model).frame; got != 1 {
		t.Errorf("frame = %d, want 1 after one tick", got)
	}
}

// TestUpdateQuit verifies the quit keys each return a command (tea.Quit).
func TestUpdateQuit(t *testing.T) {
	m := newModel("guest", "xterm-256color", "standard", 80, 24, nil)
	keys := []tea.KeyMsg{
		{Type: tea.KeyRunes, Runes: []rune{'q'}},
		{Type: tea.KeyCtrlC},
		{Type: tea.KeyEsc},
	}
	for _, k := range keys {
		if _, cmd := m.Update(k); cmd == nil {
			t.Errorf("key %q should produce a quit command", k.String())
		}
	}
}

// TestShimmerPreservesText ensures the animation styling doesn't drop or alter
// the underlying characters.
func TestShimmerPreservesText(t *testing.T) {
	const text = "✨ coming soon"
	if got := stripANSI(shimmer(nil, text, 7)); got != text {
		t.Errorf("shimmer altered text: got %q, want %q", got, text)
	}
}
