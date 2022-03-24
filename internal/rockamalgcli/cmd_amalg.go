package rockamalgcli

import (
	"bufio"
	"bytes"
	"context"
	"fmt"
	"io"
	"io/fs"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"text/template"

	"github.com/urfave/cli/v2"
)

type cmdAmalg struct {
	deps         string
	rockspec     string
	output       string
	firmware     string
	modules      []string
	rockspecTmpl *template.Template
	writer       io.Writer
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
			if cmd.deps != "" && cmd.rockspec != "" {
				return errRockspecDepsSimultaneously
			}

			if filepath.IsAbs(cmd.output) {
				return errOutputIsAbsolutePath
			}

			if !cliCtx.Args().Present() {
				return errFirmwareMissed
			}

			if err := cmd.initRockspecTempalte(); err != nil {
				return fmt.Errorf("init amalg cmd: %w", err)
			}

			cmd.firmware = cliCtx.Args().First()
			cmd.writer = cliCtx.App.Writer

			return nil
		},
		Action: func(cliCtx *cli.Context) error {
			return cmd.do(cliCtx.Context)
		},
	}
}

func (c *cmdAmalg) do(ctx context.Context) error {
	if c.deps != "" {
		defer os.RemoveAll(filepath.Dir(c.rockspec))
		if err := c.wrapWithMsg(ctx, c.generateRockspec, "Generating rockspec"); err != nil {
			return fmt.Errorf("generate rockspec: %w", err)
		}
	}

	if c.rockspec != "" {
		if err := c.wrapWithMsg(ctx, c.installDependencies, "Installing dependencies"); err != nil {
			return fmt.Errorf("install dependencies: %w", err)
		}
	}

	if err := c.wrapWithMsg(ctx, c.calculateRequires, "Calculating requires"); err != nil {
		return fmt.Errorf("calculate requires: %w", err)
	}

	fwIsDir, err := isDirectory(c.firmware)
	if err != nil {
		return fmt.Errorf("checking firmware is directory: %w", err)
	}

	if fwIsDir {
		curDir, err := os.Getwd()
		if err != nil {
			return fmt.Errorf("getting current directory: %w", err)
		}
		c.output = filepath.Join(curDir, c.output)

		if err := os.Chdir(c.firmware); err != nil {
			return fmt.Errorf("chdir: %w", err)
		}

		if err := c.gatherFirmwareDirectory(ctx); err != nil {
			return fmt.Errorf("gathering firmware directory: %w", err)
		}

		c.firmware = "main.lua"
	}

	if err := c.wrapWithMsg(ctx, c.amalgamate, "Amalgamation"); err != nil {
		return fmt.Errorf("amalgamation: %w", err)
	}

	return nil
}

func (c *cmdAmalg) generateRockspec(context.Context) error {
	depsBytes, err := os.ReadFile(c.deps)
	if err != nil {
		return fmt.Errorf("read deps: %w", err)
	}

	deps := bytes.Split(depsBytes, []byte{'\n'})

	args := struct{ Deps [][]byte }{}
	for _, d := range deps {
		if len(d) != 0 {
			args.Deps = append(args.Deps, d)
		}
	}

	tmpDir, err := os.MkdirTemp("/tmp", "rockamalg")
	if err != nil {
		return fmt.Errorf("mkdir temp: %w", err)
	}

	c.rockspec = filepath.Join(tmpDir, "generated-dev-1.rockspec")
	rf, err := os.Create(c.rockspec)
	if err != nil {
		return fmt.Errorf("create rockspec temp file: %w", err)
	}
	defer rf.Close()

	if err := c.rockspecTmpl.Execute(rf, args); err != nil {
		return fmt.Errorf("generating: %w", err)
	}

	return nil
}

func (c *cmdAmalg) installDependencies(ctx context.Context) error {
	stat, err := os.Stat(c.rockspec)
	if err != nil {
		return fmt.Errorf("rockspec file stat: %w", err)
	}

	if !stat.Mode().IsRegular() {
		return errRockspecIsNotRegularFile
	}

	cmd := exec.CommandContext(ctx, "luarocks", "install", "--only-deps", c.rockspec) //nolint:gosec,lll // rockspec is checked to be a regular file
	cmd.Stderr = os.Stderr
	if err := cmd.Run(); err != nil {
		return fmt.Errorf("run luarocks install: %w", err)
	}

	return nil
}

func (c *cmdAmalg) calculateRequires(ctx context.Context) error {
	rocksListBuf := &bytes.Buffer{}
	rocksListCmd := exec.CommandContext(ctx, "luarocks", "list", "--porcelain")
	rocksListCmd.Stdout = rocksListBuf
	rocksListCmd.Stderr = os.Stderr

	if err := rocksListCmd.Run(); err != nil {
		return fmt.Errorf("run luarocks list: %w", err)
	}

	rocksModulesBuf := &bytes.Buffer{}
	rocksScan := bufio.NewScanner(rocksListBuf)
	for rocksScan.Scan() {
		rock := strings.Fields(rocksScan.Text())[0]
		if rock == "amalg" {
			continue
		}

		rockModulesCmd := exec.CommandContext(ctx, "luarocks", "show", "--modules", rock)
		rockModulesCmd.Stdout = rocksModulesBuf
		rockModulesCmd.Stderr = os.Stderr

		if err := rockModulesCmd.Run(); err != nil {
			return fmt.Errorf("run luarocks show modules: %w", err)
		}

		rockModulesScan := bufio.NewScanner(rocksModulesBuf)
		for rockModulesScan.Scan() {
			mod := strings.TrimSuffix(rockModulesScan.Text(), ".init")
			c.modules = append(c.modules, mod)
		}

		rocksModulesBuf.Reset()
	}

	return nil
}

func (c *cmdAmalg) gatherFirmwareDirectory(context.Context) error {
	err := filepath.WalkDir(".", func(path string, de fs.DirEntry, err error) error {
		if err != nil {
			return err
		}

		if !de.Type().IsRegular() {
			return nil
		}

		if filepath.Ext(path) != ".lua" {
			return nil
		}

		mod := strings.ReplaceAll(path, "/", ".")
		mod = strings.TrimSuffix(mod, ".lua")
		mod = strings.TrimSuffix(mod, ".init")

		if mod != "main" {
			c.modules = append(c.modules, mod)
		}

		return nil
	})
	if err != nil {
		return fmt.Errorf("firmware dir walk: %w", err)
	}

	return nil
}

func (c *cmdAmalg) amalgamate(ctx context.Context) error {
	args := []string{"--debug", "-o", c.output, "-s", c.firmware}
	args = append(args, c.modules...)
	cmd := exec.CommandContext(ctx, "amalg.lua", args...)
	cmd.Stderr = os.Stderr

	if err := cmd.Run(); err != nil {
		return fmt.Errorf("amalg.lua: %w", err)
	}
	return nil
}

func (c *cmdAmalg) wrapWithMsg(ctx context.Context, fn func(context.Context) error, msg string) error {
	fmt.Fprint(c.writer, msg, "... ")
	if err := fn(ctx); err != nil {
		fmt.Fprintln(c.writer, "Failed")
		return err
	}
	fmt.Fprintln(c.writer, "Done")
	return nil
}

func (c *cmdAmalg) initRockspecTempalte() error {
	tmpl, err := template.New("<rockspec>").Parse(`
rockspec_format = '3.0'
package = 'generated'
version = 'dev-1'
source = {
    url = 'generated'
}
dependencies = {
    'lua ~> 5.3',
{{- range .Deps -}}
	'{{printf "%s" .}}',
{{- end -}}
}
`)
	if err != nil {
		return err
	}

	c.rockspecTmpl = tmpl

	return nil
}

func isDirectory(path string) (bool, error) {
	fileInfo, err := os.Stat(path)
	if err != nil {
		return false, err
	}

	return fileInfo.IsDir(), err
}
