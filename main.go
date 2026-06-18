package main

import (
	"context"
	"errors"
	"flag"
	"net"
	"os"
	"os/signal"
	"syscall"
	"time"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/log"
	"github.com/charmbracelet/ssh"
	"github.com/charmbracelet/wish"
	"github.com/charmbracelet/wish/activeterm"
	"github.com/charmbracelet/wish/bubbletea"
	"github.com/charmbracelet/wish/logging"
)

func main() {
	// Local preview mode: render the TUI in the current terminal instead of
	// starting the SSH server, so the screens can be eyeballed without ssh.
	var (
		local = flag.Bool("local", false, "render the TUI locally instead of starting the SSH server")
		user  = flag.String("user", "guest", "username to render as (use an admin name to see the admin screen)")
		term  = flag.String("term", "xterm-256color", "TERM value to report")
		font  = flag.String("font", "", "figlet font for the banner (empty = random)")
	)
	flag.Parse()

	if *local {
		if err := runLocal(*user, *term, *font); err != nil {
			log.Error("local run failed", "error", err)
			os.Exit(1)
		}
		return
	}

	if err := runServer(); err != nil {
		log.Error("server error", "error", err)
		os.Exit(1)
	}
}

// runLocal renders the TUI in the attached terminal using flag-supplied params.
func runLocal(user, term, font string) error {
	m := newModel(user, term, font, 0, 0, nil) // nil → default (local stdout) renderer
	_, err := tea.NewProgram(m, tea.WithAltScreen()).Run()
	return err
}

// runServer starts the wish SSH server and blocks until interrupted.
func runServer() error {
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
		return err
	}

	ctx, cancel := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer cancel()

	log.Info("starting SSH server", "host", host, "port", port)
	go func() {
		if err := s.ListenAndServe(); err != nil && !errors.Is(err, ssh.ErrServerClosed) {
			log.Error("could not start server", "error", err)
			cancel()
		}
	}()

	<-ctx.Done()
	log.Info("stopping SSH server")
	ctx, cancel = context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()
	if err := s.Shutdown(ctx); err != nil && !errors.Is(err, ssh.ErrServerClosed) {
		return err
	}
	return nil
}

// envOr returns the value of the environment variable key, or def if unset/empty.
func envOr(key, def string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return def
}

// teaHandler returns a new Bubble Tea program for each SSH session. It hands the
// model a renderer bound to this session so colors match the client's terminal.
func teaHandler(s ssh.Session) (tea.Model, []tea.ProgramOption) {
	pty, _, _ := s.Pty()
	r := bubbletea.MakeRenderer(s)
	m := newModel(s.User(), pty.Term, "", pty.Window.Width, pty.Window.Height, r)
	return m, []tea.ProgramOption{tea.WithAltScreen()}
}
