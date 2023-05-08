package analyzer

import (
	"bytes"
	"errors"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
)

type Analyzer struct {
	resolver *resolver
	parser   *parser
}

func New() *Analyzer {
	return &Analyzer{
		resolver: newResolver(),
		parser:   newParser(),
	}
}

func (a *Analyzer) AnalyzeRequires(luaMain, luaDir, cacheTree string) ([]string, error) {
	an := analyzer{
		cacheDir: filepath.Join(cacheTree, "share", "lua", "5.3"),
		luaDir:   luaDir,
		resolver: a.resolver,
		parser:   a.parser,
		analyzed: make(map[string]struct{}),
	}

	requires, err := an.ExtractModuleRequires(filepath.Join(luaDir, luaMain))
	if err != nil {
		return requires, fmt.Errorf("extract requires from lua main: %w", err)
	}

	for {
		next, err := an.AnalyzeRequires(requires)
		if err != nil {
			return nil, fmt.Errorf("analyze requires: %w", err)
		}

		if len(next) == 0 {
			break
		}

		requires = next
	}

	return an.Requires(), nil
}

type analyzer struct {
	cacheDir string
	luaDir   string
	resolver *resolver
	parser   *parser
	analyzed map[string]struct{}
}

func (a *analyzer) AnalyzeRequires(requires []string) ([]string, error) {
	var next []string
	for _, req := range requires {
		if _, ok := a.analyzed[req]; ok {
			continue
		}

		sf, err := a.findSourceFile(req)
		if err != nil {
			return nil, fmt.Errorf("module=%s, find source file: %w", req, err)
		}

		if sf == "" {
			continue
		}

		nextReqs, err := a.ExtractModuleRequires(sf)
		if err != nil {
			return nil, fmt.Errorf("module=%s, extract requires: %w", req, err)
		}

		next = append(next, nextReqs...)
		a.analyzed[req] = struct{}{}
	}

	return next, nil
}

func (a *analyzer) ExtractModuleRequires(path string) ([]string, error) {
	buf, err := a.generateBytecodeListing(path)
	if err != nil {
		return nil, fmt.Errorf("path=%s, generate bytecode: %w", path, err)
	}

	listing, err := a.parser.ParseListing(buf)
	if err != nil {
		return nil, fmt.Errorf("path=%s, parse listing: %w", path, err)
	}

	return a.resolver.ResolveListingRequires(listing)
}

func (a *analyzer) Requires() []string {
	s := make([]string, 0, len(a.analyzed))
	for v := range a.analyzed {
		s = append(s, v)
	}
	return s
}

func (*analyzer) generateBytecodeListing(path string) (*bytes.Buffer, error) {
	stdout := bytes.Buffer{}
	stderr := bytes.Buffer{}

	cmd := exec.Command("luac5.3", "-l", "-l", "-p", path)
	cmd.Stdout = &stdout
	cmd.Stderr = &stderr

	if err := cmd.Run(); err != nil {
		return nil, fmt.Errorf("%w (%s)", err, stderr.Bytes())
	}

	return &stdout, nil
}

func (a *analyzer) findSourceFile(require string) (string, error) {
	p := strings.ReplaceAll(require, ".", "/")
	for _, sp := range []string{p + ".lua", filepath.Join(p, "init.lua")} {
		p := filepath.Join(a.cacheDir, sp)
		if exists, err := isExists(p); err != nil {
			return "", err
		} else if exists {
			return p, nil
		}

		p = filepath.Join(a.luaDir, sp)
		if exists, err := isExists(p); err != nil {
			return "", err
		} else if exists {
			return p, nil
		}
	}

	return "", nil
}

func isExists(path string) (bool, error) {
	_, err := os.Stat(path)
	if err == nil {
		return true, nil
	}

	if errors.Is(err, os.ErrNotExist) {
		return false, nil
	}

	return false, err
}
