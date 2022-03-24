//go:build integration
// +build integration

package integration_test

import (
	"bytes"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"

	"github.com/stretchr/testify/require"
)

func TestAmalgCommand(t *testing.T) {
	t.Parallel()
	files, err := os.ReadDir("testdata/amalg")
	require.NoError(t, err)

	for _, fi := range files {
		fi := fi
		t.Run(fi.Name(), func(t *testing.T) {
			t.Parallel()
			testOpts := buildTestOpts(t, fi.Name())

			stdoutBytes := execDockerCommand(t, testOpts.amalgArgs...)
			checkExpectedWithBytes(t, testOpts.expectedStdout, stdoutBytes)
			checkExpectedWithFile(t, testOpts.expectedLua, testOpts.outLuaFileName)

			stdoutBytes = execDockerCommand(t, testOpts.luaExecArgs...)
			checkExpectedWithBytes(t, testOpts.expectedLuaExec, stdoutBytes)
		})
	}
}

type testOpts struct {
	outLuaFileName  string
	amalgArgs       []string
	luaExecArgs     []string
	expectedStdout  string
	expectedLua     string
	expectedLuaExec string
}

func buildTestOpts(t *testing.T, name string) testOpts {
	t.Helper()

	testdataPath := filepath.Join("testdata/amalg", name)

	outLuaFile, err := os.CreateTemp(testdataPath, "out_*.lua")
	require.NoError(t, err)

	t.Cleanup(func() { os.Remove(outLuaFile.Name()) })
	require.NoError(t, outLuaFile.Close())

	firmwareNameBytes, err := os.ReadFile(filepath.Join(testdataPath, "firmware"))
	require.NoError(t, err)

	firmwareName := strings.TrimSpace(string(firmwareNameBytes))

	curdir, err := os.Getwd()
	require.NoError(t, err)

	amalgArgs := []string{
		"run", "--pull", "never", "--rm", "-v", curdir + ":/app", "enapter/rockamalg",
		"amalg", "-o", outLuaFile.Name(),
	}

	depsFileName := filepath.Join(testdataPath, "deps")
	if isExist(t, depsFileName) {
		amalgArgs = append(amalgArgs, "-d", depsFileName)
	}

	rockspecFileName := filepath.Join(testdataPath, name+"-dev-1.rockspec")
	if isExist(t, rockspecFileName) {
		amalgArgs = append(amalgArgs, "-r", rockspecFileName)
	}

	amalgArgs = append(amalgArgs, filepath.Join(testdataPath, firmwareName))

	exepctedLuaFileName := filepath.Join(testdataPath, "out.lua")
	luaExecArgs := []string{
		"run", "--pull", "never", "--rm", "-v", curdir + ":/app",
		"--entrypoint", "lua5.3", "enapter/rockamalg", exepctedLuaFileName,
	}

	return testOpts{
		amalgArgs:       amalgArgs,
		luaExecArgs:     luaExecArgs,
		outLuaFileName:  outLuaFile.Name(),
		expectedStdout:  filepath.Join(testdataPath, "stdout"),
		expectedLua:     exepctedLuaFileName,
		expectedLuaExec: filepath.Join(testdataPath, "out.lua.exec"),
	}
}

func execDockerCommand(t *testing.T, args ...string) []byte {
	t.Helper()

	cmd := exec.Command("docker", args...)

	stdoutBuf := &bytes.Buffer{}
	cmd.Stdout = stdoutBuf

	stderrBuf := &bytes.Buffer{}
	cmd.Stderr = stderrBuf

	require.NoError(t, cmd.Run(), "stdout:\n%s\n\nstderr:\n%s", stdoutBuf.String(), stderrBuf.String())
	require.Empty(t, stderrBuf.String())

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
