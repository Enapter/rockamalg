package rockamalg

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
)

type Rockamalg struct {
	rockspecTmpl *template.Template
}

type Params struct {
	Dependencies string
	Rockspec     string
	Firmware     string
	Output       string
	Writer       io.Writer
}

func New() *Rockamalg {
	tmpl := template.Must(template.New("<rockspec>").Parse(`
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
`))

	return &Rockamalg{
		rockspecTmpl: tmpl,
	}
}

func (r *Rockamalg) Amalg(ctx context.Context, p Params) error {
	if p.Dependencies != "" && p.Rockspec != "" {
		return errRockspecDepsSimultaneously
	}

	if p.Firmware == "" {
		return errFirmwareMissed
	}

	a := amalg{p: p, rockspecTmpl: r.rockspecTmpl}
	return a.Do(ctx)
}

type amalg struct {
	p            Params
	modules      []string
	rockspecTmpl *template.Template
}

func (a *amalg) Do(ctx context.Context) error {
	if a.p.Dependencies != "" {
		defer os.RemoveAll(filepath.Dir(a.p.Rockspec))
		if err := a.wrapWithMsg(a.generateRockspec, "Generating rockspec")(ctx); err != nil {
			return fmt.Errorf("generate rockspec: %w", err)
		}
	}

	if a.p.Rockspec != "" {
		if err := a.wrapWithMsg(a.installDependencies, "Installing dependencies")(ctx); err != nil {
			return fmt.Errorf("install dependencies: %w", err)
		}
	}

	if err := a.wrapWithMsg(a.calculateRequires, "Calculating requires")(ctx); err != nil {
		return fmt.Errorf("calculate requires: %w", err)
	}

	fwIsDir, err := isDirectory(a.p.Firmware)
	if err != nil {
		return fmt.Errorf("checking firmware is directory: %w", err)
	}

	if fwIsDir {
		curDir, err := os.Getwd()
		if err != nil {
			return fmt.Errorf("getting current directory: %w", err)
		}
		a.p.Output = filepath.Join(curDir, a.p.Output)

		if err := os.Chdir(a.p.Firmware); err != nil {
			return fmt.Errorf("chdir: %w", err)
		}

		if err := a.gatherFirmwareDirectory(ctx); err != nil {
			return fmt.Errorf("gathering firmware directory: %w", err)
		}

		a.p.Firmware = "main.lua"
	}

	if err := a.wrapWithMsg(a.amalgamate, "Amalgamation")(ctx); err != nil {
		return fmt.Errorf("amalgamation: %w", err)
	}

	return nil
}

func (a *amalg) generateRockspec(context.Context) error {
	depsBytes, err := os.ReadFile(a.p.Dependencies)
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

	a.p.Rockspec = filepath.Join(tmpDir, "generated-dev-1.rockspec")
	rf, err := os.Create(a.p.Rockspec)
	if err != nil {
		return fmt.Errorf("create rockspec temp file: %w", err)
	}
	defer rf.Close()

	if err := a.rockspecTmpl.Execute(rf, args); err != nil {
		return fmt.Errorf("generating: %w", err)
	}

	return nil
}

func (a *amalg) installDependencies(ctx context.Context) error {
	stat, err := os.Stat(a.p.Rockspec)
	if err != nil {
		return fmt.Errorf("rockspec file stat: %w", err)
	}

	if !stat.Mode().IsRegular() {
		return errRockspecIsNotRegularFile
	}

	cmd := exec.CommandContext(ctx, "luarocks", "install", "--only-deps", a.p.Rockspec) //nolint:gosec,lll // rockspec is checked to be a regular file
	cmd.Stderr = os.Stderr
	if err := cmd.Run(); err != nil {
		return fmt.Errorf("run luarocks install: %w", err)
	}

	return nil
}

func (a *amalg) calculateRequires(ctx context.Context) error {
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
			a.modules = append(a.modules, mod)
		}

		rocksModulesBuf.Reset()
	}

	return nil
}

func (a *amalg) gatherFirmwareDirectory(context.Context) error {
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
			a.modules = append(a.modules, mod)
		}

		return nil
	})
	if err != nil {
		return fmt.Errorf("firmware dir walk: %w", err)
	}

	return nil
}

func (a *amalg) amalgamate(ctx context.Context) error {
	args := []string{"--debug", "-o", a.p.Output, "-s", a.p.Firmware}
	args = append(args, a.modules...)
	cmd := exec.CommandContext(ctx, "amalg.lua", args...)
	cmd.Stderr = os.Stderr

	if err := cmd.Run(); err != nil {
		return fmt.Errorf("amalg.lua: %w", err)
	}
	return nil
}

func (a *amalg) wrapWithMsg(fn func(context.Context) error, msg string) func(context.Context) error {
	if a.p.Writer == nil {
		return fn
	}

	return func(ctx context.Context) error {
		fmt.Fprint(a.p.Writer, msg, "... ")
		if err := fn(ctx); err != nil {
			fmt.Fprintln(a.p.Writer, "Failed")
			return err
		}
		fmt.Fprintln(a.p.Writer, "Done")
		return nil
	}
}

func isDirectory(path string) (bool, error) {
	fileInfo, err := os.Stat(path)
	if err != nil {
		return false, err
	}

	return fileInfo.IsDir(), err
}
