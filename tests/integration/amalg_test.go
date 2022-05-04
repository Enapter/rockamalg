//go:build integration
// +build integration

package integration_test

import (
	"bytes"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"

	"github.com/stretchr/testify/require"
)

type rockstype int

const (
	publicRocks rockstype = iota
	privateRocks
)

func TestAmalgCommandPublicRocks(t *testing.T) {
	t.Parallel()

	testAmalg(t, "testdata/amalg", publicRocks)
}

func TestAmalgCommandPrivateRocks(t *testing.T) {
	t.Parallel()

	testAmalg(t, "testdata/amalg-private", privateRocks)
}

func testAmalg(t *testing.T, testdataDir string, rt rockstype) {
	t.Helper()

	files, err := os.ReadDir(testdataDir)
	require.NoError(t, err)

	for _, fi := range files {
		fi := fi
		for _, isolate := range []bool{false, true} {
			isolate := isolate
			t.Run(fmt.Sprintf("%s isolate %v", fi.Name(), isolate), func(t *testing.T) {
				t.Parallel()
				testOpts := buildTestOpts(t, fi.Name(), testdataDir, isolate, rt)

				stdoutBytes := execDockerCommand(t, testOpts.amalgArgs...)
				checkExpectedWithBytes(t, testOpts.expectedStdout, stdoutBytes)
				checkExpectedWithFile(t, testOpts.expectedLua, testOpts.outLuaFileName)

				stdoutBytes = execDockerCommand(t, testOpts.luaExecArgs...)
				checkExpectedWithBytes(t, testOpts.expectedLuaExec, stdoutBytes)
			})
		}
	}
}

type testOpts struct {
	outLuaFileName   string
	amalgArgs        []string
	luaExecArgs      []string
	expectedStdout   string
	expectedLua      string
	expectedLuaExec  string
	luaPath          string
	depsFileName     string
	rockspecFileName string
}

//nolint:funlen // setup a large number of fields
func buildTestOpts(t *testing.T, name string, testdataDir string, isolate bool, rt rockstype) testOpts {
	t.Helper()

	o := out{lua: "out.lua", stdout: "stdout"}
	if isolate {
		o.SetIsolateOut()
	}

	testdataPath := filepath.Join(testdataDir, name)

	outLuaFile, err := os.CreateTemp(testdataPath, "out_*.lua")
	require.NoError(t, err)

	t.Cleanup(func() { os.Remove(outLuaFile.Name()) })
	require.NoError(t, outLuaFile.Close())

	luaNameBytes, err := os.ReadFile(filepath.Join(testdataPath, "lua"))
	require.NoError(t, err)

	luaName := strings.TrimSpace(string(luaNameBytes))

	curdir, err := os.Getwd()
	require.NoError(t, err)

	amalgArgs := []string{
		"run", "--pull", "never", "--rm",
		"-v", curdir + ":/app",
	}
	if rt == privateRocks {
		amalgArgs = append(amalgArgs,
			"-v", filepath.Join(curdir, "testdata/rocks")+":/opt/rocks",
		)
	}
	amalgArgs = append(amalgArgs, "enapter/rockamalg", "amalg", "-o", outLuaFile.Name())

	depsFileName := filepath.Join(testdataPath, "deps")
	if isExist(t, depsFileName) {
		amalgArgs = append(amalgArgs, "-d", depsFileName)
	} else {
		depsFileName = ""
	}

	rockspecFileName := filepath.Join(testdataPath, name+"-dev-1.rockspec")
	if isExist(t, rockspecFileName) {
		amalgArgs = append(amalgArgs, "-r", rockspecFileName)
	} else {
		rockspecFileName = ""
	}

	if isolate {
		amalgArgs = append(amalgArgs, "-i")
	}

	if rt == privateRocks {
		amalgArgs = append(amalgArgs, "--rocks-server", "/opt/rocks")
	}

	amalgArgs = append(amalgArgs, filepath.Join(testdataPath, luaName))

	exepctedLuaFileName := filepath.Join(testdataPath, o.lua)
	luaExecArgs := []string{
		"run", "--pull", "never", "--rm", "-v", curdir + ":/app",
		"--entrypoint", "lua5.3", "enapter/rockamalg", exepctedLuaFileName,
	}

	return testOpts{
		amalgArgs:        amalgArgs,
		luaExecArgs:      luaExecArgs,
		outLuaFileName:   outLuaFile.Name(),
		expectedStdout:   filepath.Join(testdataPath, o.stdout),
		expectedLua:      exepctedLuaFileName,
		expectedLuaExec:  filepath.Join(testdataPath, "out.lua.exec"),
		luaPath:          filepath.Join(testdataPath, luaName),
		depsFileName:     depsFileName,
		rockspecFileName: rockspecFileName,
	}
}

type out struct {
	lua    string
	stdout string
}

func (o *out) SetIsolateOut() {
	const pref = "isolated."
	o.lua = pref + o.lua
	o.stdout = pref + o.stdout
}

func execDockerCommand(t *testing.T, args ...string) []byte {
	t.Helper()

	cmd := exec.Command("docker", args...)

	stdoutBuf := &bytes.Buffer{}
	cmd.Stdout = stdoutBuf

	stderrBuf := &bytes.Buffer{}
	cmd.Stderr = stderrBuf

	require.NoError(t, cmd.Run(), "stdout:\n%s\n\nstderr:\n%s", stdoutBuf.String(), stderrBuf.String())
	require.Empty(t, stderrBuf.String(), "stdout: %s", stdoutBuf.String())

	return stdoutBuf.Bytes()
}

func checkExpectedWithFile(t *testing.T, exepctedFileName, actualFileName string) {
	t.Helper()

	actuaData, err := os.ReadFile(actualFileName)
	require.NoError(t, err)

	checkExpectedWithBytes(t, exepctedFileName, actuaData)
}

func checkExpectedWithBytes(t *testing.T, exepctedFileName string, actualData []byte) {
	t.Helper()

	if update {
		err := os.WriteFile(exepctedFileName, actualData, 0o600)
		require.NoError(t, err)
	} else {
		expected, err := os.ReadFile(exepctedFileName)
		require.NoError(t, err)
		require.Equal(t, string(expected), string(actualData))
	}
}

func isExist(t *testing.T, path string) bool {
	t.Helper()

	_, err := os.Stat(path)
	if err == nil {
		return true
	}

	if !os.IsNotExist(err) {
		t.Fatalf("stat finished with error: %v", err)
	}

	return false
}
