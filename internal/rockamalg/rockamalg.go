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
	Isolate      bool
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
	defer a.cleanup()

	return a.Do(ctx)
}

type amalg struct {
	p            Params
	firmwareDir  string
	rocksTree    string
	modules      []string
	rockspecTmpl *template.Template
	cleanupFns   []func()
}

func (a *amalg) Do(ctx context.Context) error {
	if a.p.Dependencies != "" {
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

	if !filepath.IsAbs(a.p.Output) {
		curDir, err := os.Getwd()
		if err != nil {
			return fmt.Errorf("getting current directory: %w", err)
		}
		a.p.Output = filepath.Join(curDir, a.p.Output)
	}

	fwIsDir, err := isDirectory(a.p.Firmware)
	if err != nil {
		return fmt.Errorf("checking firmware is directory: %w", err)
	}

	if !fwIsDir {
		a.firmwareDir = filepath.Dir(a.p.Firmware)
		a.p.Firmware = filepath.Base(a.p.Firmware)
	} else {
		a.firmwareDir = a.p.Firmware

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

	tmpDir, err := os.MkdirTemp("/tmp", "genrockspec")
	if err != nil {
		return fmt.Errorf("mkdir temp: %w", err)
	}
	a.cleanupFns = append(a.cleanupFns, func() { os.RemoveAll(tmpDir) })

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

	if a.p.Isolate {
		tmpDir, err := os.MkdirTemp("/tmp", "luarocks_deps_")
		if err != nil {
			return fmt.Errorf("mkdir temp: %w", err)
		}
		a.cleanupFns = append(a.cleanupFns, func() { os.RemoveAll(tmpDir) })
		a.rocksTree = tmpDir
	}

	cmd := a.buildLuaRocksCommand(ctx, "install", "--only-deps", a.p.Rockspec)
	cmd.Stderr = os.Stdout
	if err := cmd.Run(); err != nil {
		return fmt.Errorf("run luarocks install: %w", err)
	}

	return nil
}

func (a *amalg) calculateRequires(ctx context.Context) error {
	rocksListBuf := &bytes.Buffer{}
	rocksListCmd := a.buildLuaRocksCommand(ctx, "list", "--porcelain")
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

		rockModulesCmd := a.buildLuaRocksCommand(ctx, "show", "--modules", rock)
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
	err := filepath.WalkDir(a.firmwareDir, func(path string, de fs.DirEntry, err error) error {
		if err != nil {
			return err
		}

		if !de.Type().IsRegular() {
			return nil
		}

		if filepath.Ext(path) != ".lua" {
			return nil
		}

		mod := strings.TrimPrefix(path, a.firmwareDir+string(os.PathSeparator))
		mod = strings.ReplaceAll(mod, "/", ".")
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
	cmd.Dir = a.firmwareDir
	cmd.Stderr = os.Stderr

	if a.p.Isolate {
		outBuf := &bytes.Buffer{}
		rockLuaPathCmd := a.buildLuaRocksCommand(ctx, "path")
		rockLuaPathCmd.Stdout = outBuf

		if err := rockLuaPathCmd.Run(); err != nil {
			return fmt.Errorf("run luarocks path: %w", err)
		}

		cmd.Env = append(cmd.Env, a.extractLuaPathEnv(outBuf.String()))
	}

	if err := cmd.Run(); err != nil {
		return fmt.Errorf("amalg.lua: %w", err)
	}
	return nil
}

func (a *amalg) buildLuaRocksCommand(ctx context.Context, args ...string) *exec.Cmd {
	if a.rocksTree != "" {
		args = append([]string{"--tree", a.rocksTree}, args...)
	}
	return exec.CommandContext(ctx, "luarocks", args...)
}

func (*amalg) extractLuaPathEnv(data string) string {
	for _, s := range strings.Fields(data) {
		if strings.HasPrefix(s, "LUA_PATH='") {
			return strings.Replace(strings.TrimSuffix(s, "'"), "LUA_PATH='", "LUA_PATH=", 1)
		}
	}
	return ""
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

func (a *amalg) cleanup() {
	for _, fn := range a.cleanupFns {
		fn()
	}
}

func isDirectory(path string) (bool, error) {
	fileInfo, err := os.Stat(path)
	if err != nil {
		return false, err
	}

	return fileInfo.IsDir(), err
}
