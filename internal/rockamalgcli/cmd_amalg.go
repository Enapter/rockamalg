package rockamalgcli

import (
	"path/filepath"

	"github.com/urfave/cli/v2"

	"github.com/enapter/rockamalg/internal/rockamalg"
)

type cmdAmalg struct {
	deps         string
	rockspec     string
	output       string
	lua          string
	isolate      bool
	disableDebug bool
	rocksServer  string
}

//nolint:funlen // large number of flags
func buildCmdAmalg() *cli.Command {
	var cmd cmdAmalg

	return &cli.Command{
		Name:      "amalg",
		Usage:     "Amalgamates Lua files with all dependencies inside one Lua file.",
		ArgsUsage: "lua",
		Description: `
The lua should be a single Lua file or directory with main.lua and other Lua files.

The dependencies file should be in the Luarocks format.

See the tutorial https://developers.enapter.com/docs/tutorial/lua-complex/introduction to learn more.
`,
		Flags: []cli.Flag{
			&cli.StringFlag{
				Name:        "deps",
				Aliases:     []string{"d"},
				Usage:       "Use dependencies file",
				Destination: &cmd.deps,
			},
			&cli.StringFlag{
				Name:        "rockspec",
				Aliases:     []string{"r"},
				Usage:       "Use rockspec file for dependencies",
				Destination: &cmd.rockspec,
			},
			&cli.StringFlag{
				Name:        "output",
				Aliases:     []string{"o"},
				Usage:       "Output Lua file name",
				Destination: &cmd.output,
				Required:    true,
			},
			&cli.BoolFlag{
				Name:        "isolate",
				Aliases:     []string{"i"},
				Usage:       "Enable isolate mode",
				Destination: &cmd.isolate,
			},
			&cli.BoolFlag{
				Name:        "disable-debug",
				Usage:       "Disable debug mode",
				Destination: &cmd.disableDebug,
			},
			&cli.StringFlag{
				Name:        "rocks-server",
				Aliases:     []string{"s"},
				Usage:       "Use custom rocks server",
				Destination: &cmd.rocksServer,
			},
		},
		Before: func(cliCtx *cli.Context) error {
			if filepath.IsAbs(cmd.output) {
				return errOutputIsAbsolutePath
			}

			cmd.lua = cliCtx.Args().First()

			return nil
		},
		Action: func(cliCtx *cli.Context) error {
			return rockamalg.New(cmd.rocksServer).
				Amalg(cliCtx.Context,
					rockamalg.Params{
						Dependencies: cmd.deps,
						Rockspec:     cmd.rockspec,
						Lua:          cmd.lua,
						Output:       cmd.output,
						Writer:       cliCtx.App.Writer,
						Isolate:      cmd.isolate,
						DisableDebug: cmd.disableDebug,
					})
		},
	}
}
