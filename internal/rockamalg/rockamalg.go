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
	"sync"
	"text/template"

	"github.com/enapter/rockamalg/internal/archive"
	"github.com/enapter/rockamalg/internal/rockamalg/analyzer"
)

type Rockamalg struct {
	rockspecTmpl  *template.Template
	rocksServer   string
	analyzer      *analyzer.Analyzer
	commandExecMu sync.Mutex
}

type AmalgParams struct {
	Dependencies string
	Rockspec     string
	Lua          string
	Output       string
	Vendor       string
	Isolate      bool
	DisableDebug bool
	AllowDevDeps bool
	Writer       io.Writer
}

type Params struct {
	RocksServer string
}

func New(p Params) *Rockamalg {
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
		rocksServer:  p.RocksServer,
		analyzer:     analyzer.New(),
	}
}

func (r *Rockamalg) Amalg(ctx context.Context, p AmalgParams) error {
	if p.Dependencies != "" && p.Rockspec != "" {
		return errRockspecDepsSimultaneously
	}

	if p.Lua == "" {
		return errLuaMissed
	}

	runCmdSync := func(cmd *exec.Cmd) (*bytes.Buffer, error) {
		r.commandExecMu.Lock()
		defer r.commandExecMu.Unlock()

		outBuf := &bytes.Buffer{}
		cmd.Stdout = outBuf
		errBuf := &bytes.Buffer{}
		cmd.Stderr = errBuf

		if err := cmd.Run(); err != nil {
			return nil, fmt.Errorf("%w (%s)", err, errBuf.Bytes())
		}

		return outBuf, nil
	}

	a := amalg{
		p:            p,
		rockspecTmpl: r.rockspecTmpl,
		rocksServer:  r.rocksServer,
		runCmd:       runCmdSync,
		analyzer:     r.analyzer,
	}
	defer a.cleanup()

	return a.Do(ctx)
}

type amalg struct {
	p            AmalgParams
	luaDir       string
	luaMain      string
	singleFile   bool
	tree         string
	modules      []string
	rockspecTmpl *template.Template
	rocksServer  string
	cleanupFns   []func()
	analyzer     *analyzer.Analyzer
	runCmd       func(cmd *exec.Cmd) (*bytes.Buffer, error)
}

func (a *amalg) Do(ctx context.Context) error {
	if err := a.wrapWithMsg(a.setupConfig, "Setting up configuration")(ctx); err != nil {
		return fmt.Errorf("set up configuration: %w", err)
	}

	if a.p.Dependencies != "" {
		if err := a.wrapWithMsg(a.generateRockspec, "Generating rockspec")(ctx); err != nil {
			return fmt.Errorf("generate rockspec: %w", err)
		}
	}

	if a.p.Rockspec != "" {
		if err := a.wrapWithMsg(a.installDependencies, "Installing dependencies")(ctx); err != nil {
			return fmt.Errorf("install dependencies: %w", err)
		}

		if a.p.Vendor != "" {
			if err := a.wrapWithMsg(a.buildVendorArchive, "Building vendor archive")(ctx); err != nil {
				return fmt.Errorf("build vendor archive: %w", err)
			}
		}
	}

	if err := a.wrapWithMsg(a.calculateRequires, "Calculating requires")(ctx); err != nil {
		return fmt.Errorf("calculate requires: %w", err)
	}

	if err := a.wrapWithMsg(a.amalgamate, "Amalgamating")(ctx); err != nil {
		return fmt.Errorf("amalgamate: %w", err)
	}

	if err := a.wrapWithMsg(a.cleanupResult, "Cleaning up result")(ctx); err != nil {
		return fmt.Errorf("clean up result: %w", err)
	}

	return nil
}

func (a *amalg) setupConfig(_ context.Context) error {
	tmpDir, err := os.MkdirTemp("/tmp", "luarocks_deps_")
	if err != nil {
		return fmt.Errorf("mkdir temp: %w", err)
	}
	a.cleanupFns = append(a.cleanupFns, func() { os.RemoveAll(tmpDir) })
	a.tree = tmpDir

	if !filepath.IsAbs(a.p.Output) {
		curDir, err := os.Getwd()
		if err != nil {
			return fmt.Errorf("getting current directory: %w", err)
		}
		a.p.Output = filepath.Join(curDir, a.p.Output)
	}

	luaIsDir, err := isDirectory(a.p.Lua)
	if err != nil {
		return fmt.Errorf("checking lua is directory: %w", err)
	}

	if luaIsDir {
		a.luaDir = a.p.Lua
		a.luaMain = "main.lua"
	} else {
		a.luaDir = filepath.Dir(a.p.Lua)
		a.luaMain = filepath.Base(a.p.Lua)
		a.singleFile = true
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

	args := []string{"install", "--only-deps", a.p.Rockspec}
	if a.rocksServer != "" {
		args = append(args, "--only-server="+a.rocksServer)
	}

	if a.p.AllowDevDeps {
		args = append(args, "--dev")
	}

	cmd := a.buildLuaRocksCommand(ctx, args...)
	if _, err := a.runCmd(cmd); err != nil {
		return fmt.Errorf("run luarocks install: %w", err)
	}

	return nil
}

func (a *amalg) buildVendorArchive(_ context.Context) error {
	return archive.ZipDirToFile(a.tree, a.p.Vendor)
}

func (a *amalg) calculateRequires(ctx context.Context) error {
	var err error
	if a.p.Isolate {
		err = a.calculateIsolatedRequires(ctx)
	} else {
		err = a.analyzeRequires(ctx)
	}

	return err
}

func (a *amalg) amalgamate(ctx context.Context) error {
	args := []string{"-o", a.p.Output, "-s", a.luaMain}
	if !a.p.DisableDebug {
		args = append(args, "--debug")
	}
	args = append(args, a.modules...)
	cmd := exec.CommandContext(ctx, "amalg.lua", args...)
	cmd.Dir = a.luaDir

	rockLuaPathCmd := a.buildLuaRocksCommand(ctx, "path")
	output, err := a.runCmd(rockLuaPathCmd)
	if err != nil {
		return fmt.Errorf("run luarocks path: %w", err)
	}
	cmd.Env = append(cmd.Env, a.extractLuaPathEnv(output.String()))

	if _, err := a.runCmd(cmd); err != nil {
		return fmt.Errorf("amalg.lua: %w", err)
	}
	return nil
}

func (a *amalg) cleanupResult(_ context.Context) error {
	f, err := os.OpenFile(a.p.Output, os.O_RDWR, 0)
	if err != nil {
		return fmt.Errorf("open: %w", err)
	}

	buf, err := io.ReadAll(f)
	if err != nil {
		return fmt.Errorf("read: %w", err)
	}

	buf = bytes.ReplaceAll(buf, []byte(a.tree), []byte("/usr/local"))

	if err := f.Truncate(0); err != nil {
		return fmt.Errorf("truncate: %w", err)
	}

	if _, err := f.Seek(0, io.SeekStart); err != nil {
		return fmt.Errorf("seek: %w", err)
	}

	if _, err := f.Write(buf); err != nil {
		return fmt.Errorf("write: %w", err)
	}

	return nil
}

func (a *amalg) calculateIsolatedRequires(ctx context.Context) error {
	if err := a.calculateLuaRocksRequires(ctx); err != nil {
		return fmt.Errorf("calculate luarocks requires: %w", err)
	}

	if !a.singleFile {
		if err := a.gatherLuaDirectory(ctx); err != nil {
			return fmt.Errorf("gather lua directory: %w", err)
		}
	}

	return nil
}

func (a *amalg) analyzeRequires(context.Context) error {
	reqs, err := a.analyzer.AnalyzeRequires(a.luaMain, a.luaDir, a.tree)
	if err != nil {
		return fmt.Errorf("analyze requires: %w", err)
	}

	a.modules = append(a.modules, reqs...)

	return nil
}

func (a *amalg) calculateLuaRocksRequires(ctx context.Context) error {
	rocksListCmd := a.buildLuaRocksCommand(ctx, "list", "--porcelain")
	rocksListBuf, err := a.runCmd(rocksListCmd)
	if err != nil {
		return fmt.Errorf("run luarocks list: %w", err)
	}

	rocksScan := bufio.NewScanner(rocksListBuf)
	for rocksScan.Scan() {
		rock := strings.Fields(rocksScan.Text())[0]
		if rock == "amalg" {
			continue
		}

		rockModulesCmd := a.buildLuaRocksCommand(ctx, "show", "--modules", rock)
		rocksModulesBuf, err := a.runCmd(rockModulesCmd)
		if err != nil {
			return fmt.Errorf("run luarocks show modules: %w", err)
		}

		rockModulesScan := bufio.NewScanner(rocksModulesBuf)
		for rockModulesScan.Scan() {
			mod := strings.TrimSuffix(rockModulesScan.Text(), ".init")
			a.modules = append(a.modules, mod)
		}
	}

	return nil
}

func (a *amalg) gatherLuaDirectory(context.Context) error {
	err := filepath.WalkDir(a.luaDir, func(path string, de fs.DirEntry, err error) error {
		if err != nil {
			return err
		}

		if !de.Type().IsRegular() {
			return nil
		}

		if filepath.Ext(path) != ".lua" {
			return nil
		}

		mod := strings.TrimPrefix(path, a.luaDir+string(os.PathSeparator))
		mod = strings.ReplaceAll(mod, "/", ".")
		mod = strings.TrimSuffix(mod, ".lua")
		mod = strings.TrimSuffix(mod, ".init")

		if mod != "main" {
			a.modules = append(a.modules, mod)
		}

		return nil
	})
	if err != nil {
		return fmt.Errorf("lua dir walk: %w", err)
	}

	return nil
}

func (a *amalg) buildLuaRocksCommand(ctx context.Context, args ...string) *exec.Cmd {
	args = append([]string{"--tree", a.tree}, args...)
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
