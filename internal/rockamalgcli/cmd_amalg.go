package rockamalgcli

import (
	"path/filepath"

	"github.com/urfave/cli/v2"

	"github.com/enapter/rockamalg/internal/rockamalg"
)

type cmdAmalg struct {
	deps     string
	rockspec string
	output   string
	firmware string
}

func buildCmdAmalg() *cli.Command {
	var cmd cmdAmalg

	return &cli.Command{
		Name:      "amalg",
		Usage:     "Amalgamates Lua files with all dependencies inside one Lua file.",
		ArgsUsage: "firmware",
		Description: `
The firmware should be a single Lua file or directory with main.lua and other Lua files.

The dependencies file should be in the Luarocks format.

See the tutorial https://developers.enapter.com/docs/tutorial/lua-complex/multi-file to learn more.
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
				Usage:       "Output firmware file name",
				Destination: &cmd.output,
				Required:    true,
			},
		},
		Before: func(cliCtx *cli.Context) error {
			if filepath.IsAbs(cmd.output) {
				return errOutputIsAbsolutePath
			}

			cmd.firmware = cliCtx.Args().First()

			return nil
		},
		Action: func(cliCtx *cli.Context) error {
			return rockamalg.New().
				Amalg(cliCtx.Context,
					rockamalg.Params{
						Dependencies: cmd.deps,
						Rockspec:     cmd.rockspec,
						Firmware:     cmd.firmware,
						Output:       cmd.output,
						Writer:       cliCtx.App.Writer,
					})
		},
	}
}
