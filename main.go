package main

import (
	"context"
	"errors"
	"fmt"
	"math/rand/v2"
	"net"
	"os"
	"os/signal"
	"strings"
	"syscall"
	"time"

	"github.com/common-nighthawk/go-figure"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
	"github.com/charmbracelet/log"
	"github.com/charmbracelet/ssh"
	"github.com/charmbracelet/wish"
	"github.com/charmbracelet/wish/activeterm"
	"github.com/charmbracelet/wish/bubbletea"
	"github.com/charmbracelet/wish/logging"
)

func main() {
	var (
		host        = envOr("HOST", "0.0.0.0")
		port        = envOr("PORT", "2222")
		hostKeyPath = envOr("HOST_KEY_PATH", ".ssh/ssh_host_ed25519")
	)

	s, err := wish.NewServer(
		wish.WithAddress(net.JoinHostPort(host, port)),
		wish.WithHostKeyPath(hostKeyPath),
		wish.WithMiddleware(
			bubbletea.Middleware(teaHandler),
			activeterm.Middleware(), // ensure a PTY is attached
			logging.Middleware(),
		),
	)
	if err != nil {
		log.Error("could not start server", "error", err)
		os.Exit(1)
	}

	ctx, cancel := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer cancel()

	log.Info("starting SSH server", "host", host, "port", port)
	go func() {
		if err = s.ListenAndServe(); err != nil && !errors.Is(err, ssh.ErrServerClosed) {
			log.Error("could not start server", "error", err)
			cancel()
		}
	}()

	<-ctx.Done()
	log.Info("stopping SSH server")
	ctx, cancel = context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()
	if err := s.Shutdown(ctx); err != nil && !errors.Is(err, ssh.ErrServerClosed) {
		log.Error("could not stop server", "error", err)
	}
}

// envOr returns the value of the environment variable key, or def if unset/empty.
func envOr(key, def string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return def
}

// figletFonts is a curated set of go-figure fonts that render legibly and
// aren't absurdly wide. One is chosen at random per login.
var figletFonts = []string{
	"standard", "slant", "small", "smslant", "big", "doom", "ogre",
	"speed", "colossal", "shadow", "script", "drpepper", "chunky",
	"graffiti", "basic", "banner", "epic", "larry3d", "starwars", "block",
}

// teaHandler returns a new Bubble Tea program for each SSH session.
func teaHandler(s ssh.Session) (tea.Model, []tea.ProgramOption) {
	pty, _, _ := s.Pty()
	m := model{
		term:   pty.Term,
		width:  pty.Window.Width,
		height: pty.Window.Height,
		user:   s.User(),
		admin:  isAdmin(s.User()),
		font:   figletFonts[rand.IntN(len(figletFonts))],
	}
	return m, []tea.ProgramOption{tea.WithAltScreen()}
}

// figlet renders text as ASCII art in the given font, trimmed of blank edges.
func figlet(text, font string) string {
	out := figure.NewFigure(text, font, false).String()
	return strings.Trim(out, "\n")
}

type model struct {
	term   string
	width  int
	height int
	user   string
	admin  bool
	font   string // random figlet font for this session
}

// isAdmin reports whether the connecting username is in the ADMIN_USERS list
// (comma-separated, defaults to "chakri"). Username-based — fine for a fun
// easter-egg screen; not a security boundary.
func isAdmin(user string) bool {
	for a := range strings.SplitSeq(envOr("ADMIN_USERS", "chakri"), ",") {
		if strings.EqualFold(strings.TrimSpace(a), user) {
			return true
		}
	}
	return false
}

func (m model) Init() tea.Cmd {
	return nil
}

func (m model) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	switch msg := msg.(type) {
	case tea.WindowSizeMsg:
		m.width = msg.Width
		m.height = msg.Height
	case tea.KeyMsg:
		switch msg.String() {
		case "q", "ctrl+c", "esc":
			return m, tea.Quit
		}
	}
	return m, nil
}

func (m model) View() string {
	if m.admin {
		return m.adminView()
	}

	accent := lipgloss.Color("212")
	dim := lipgloss.NewStyle().Foreground(lipgloss.Color("245"))

	banner := lipgloss.NewStyle().Bold(true).Foreground(accent).
		Render(figlet("chakri", m.font))
	subtitle := lipgloss.NewStyle().Foreground(accent).Render("terminal.chakri.me")

	body := lipgloss.JoinVertical(lipgloss.Left,
		banner,
		subtitle,
		"",
		fmt.Sprintf("Welcome, %s 👋", m.user),
		"",
		dim.Render(fmt.Sprintf("connected over SSH · %s · font: %s", m.term, m.font)),
		dim.Render("press q to quit"),
	)

	return lipgloss.NewStyle().Padding(1, 2).Render(body)
}

// adminView greets the operator with the deploy cheat-sheet instead of the
// public welcome screen.
func (m model) adminView() string {
	accent := lipgloss.Color("212")

	banner := lipgloss.NewStyle().Bold(true).Foreground(accent).
		Render(figlet("deploy", m.font))

	key := lipgloss.NewStyle().Bold(true).Foreground(accent)
	dim := lipgloss.NewStyle().Foreground(lipgloss.Color("245"))

	steps := lipgloss.JoinVertical(lipgloss.Left,
		lipgloss.NewStyle().Bold(true).Foreground(accent).
			Render(fmt.Sprintf("welcome back, %s 😎", m.user)),
		"",
		lipgloss.NewStyle().Bold(true).Render("🚀 Ship a new version"),
		"",
		"  "+key.Render("make deploy")+dim.Render("   # build → ship → swap → restart"),
		"",
		lipgloss.NewStyle().Bold(true).Render("🔧 Admin the box  (port 2222)"),
		"",
		"  "+key.Render("ssh -p 2222 root@terminal.chakri.me"),
		"  "+dim.Render("systemctl status terminal-app"),
		"  "+dim.Render("journalctl -u terminal-app -f"),
		"",
		dim.Render("  full runbook → DEPLOY.md"),
	)

	box := lipgloss.NewStyle().
		Border(lipgloss.RoundedBorder()).
		BorderForeground(accent).
		Padding(1, 3).
		Render(lipgloss.JoinVertical(lipgloss.Left, banner, "", steps))

	footer := dim.Render(fmt.Sprintf("logged in as %s · %s · press q to quit", m.user, m.term))

	return lipgloss.NewStyle().Padding(1, 2).Render(
		lipgloss.JoinVertical(lipgloss.Left, box, "", footer),
	)
}
