package main

import (
	"context"
	"fmt"
	"os"
	"os/signal"
	"runtime"

	"github.com/urfave/cli/v2"

	"github.com/enapter/rockamalg/internal/rockamalgcli"
)

//nolint:gochecknoglobals // because sets up via ldflags
var (
	version = "dev"
	commit  = "none"
	date    = "unknown"
)

func main() {
	initBuildDate()
	if err := run(); err != nil {
		fmt.Println("")
		fmt.Println("Error:", err)
		os.Exit(1)
	}
}

func run() error {
	cli.VersionPrinter = func(c *cli.Context) {
		fmt.Printf("Rockamalg %s, commit %s, built at %s, Go version %s\n",
			c.App.Version, commit, date, runtime.Version())
	}

	app := rockamalgcli.NewApp()
	app.Version = version

	ctx, cancel := signal.NotifyContext(context.Background(), os.Interrupt)
	defer cancel()

	return app.RunContext(ctx, os.Args)
}

func initBuildDate() {
	s, err := os.Stat(os.Args[0])
	if err != nil {
		return
	}

	date = s.ModTime().Format("2006-01-02 15:04:05")
}
