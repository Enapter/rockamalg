//go:build integration
// +build integration

package integration_test

import (
	"bytes"
	"fmt"
	"io"
	"io/fs"
	"os"
	"os/exec"
	"path/filepath"
	"reflect"
	"regexp"
	"strings"
	"testing"

	"github.com/stretchr/testify/require"

	"github.com/enapter/rockamalg/internal/archive"
)

type rockstype int

const (
	publicRocks rockstype = iota
	privateRocks
	devRocksTest
	vendoredRocks
)

func TestAmalgCommandPublicRocks(t *testing.T) {
	t.Parallel()

	testAmalg(t, "testdata/amalg", publicRocks)
}

func TestAmalgCommandPrivateRocks(t *testing.T) {
	t.Parallel()

	testAmalg(t, "testdata/amalg-private", privateRocks)
}

func TestAmalgCommandPartlyVendored(t *testing.T) {
	t.Parallel()

	testAmalg(t, "testdata/amalg-partly-vendor", vendoredRocks)
}

func TestAmalgDevDeps(t *testing.T) {
	t.Parallel()

	tests := []struct {
		name         string
		allowDevDeps bool
	}{
		{name: "without dev deps"},
		{name: "with dev deps", allowDevDeps: true},
	}

	testdataPath := "testdata/amalg-dev"
	curdir, err := os.Getwd()
	require.NoError(t, err)

	for _, tc := range tests {
		tc := tc
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()
			amalgArgs := []string{
				"run", "--pull", "never", "--rm",
				"-v", curdir + ":/app",
				"-v", filepath.Join(curdir, testdataPath, "luarocks") + ":/usr/local/bin/luarocks",
			}

			amalgArgs = append(amalgArgs, "enapter/rockamalg", "amalg",
				"-d", filepath.Join(testdataPath, "deps"),
				"-o", filepath.Join(testdataPath, "out.lua"))

			expectedStdout := filepath.Join(testdataPath, "stdout")
			if tc.allowDevDeps {
				amalgArgs = append(amalgArgs, "--allow-dev-dependencies")
				expectedStdout += ".dev"
			}

			amalgArgs = append(amalgArgs, filepath.Join(testdataPath, "test.lua"))

			dockerCmd := exec.Command("docker", amalgArgs...)

			stdoutBuf := &bytes.Buffer{}
			dockerCmd.Stdout = stdoutBuf

			require.Error(t, dockerCmd.Run())

			fixDepsDirRe := regexp.MustCompile(`/tmp/luarocks_deps_\d+`)
			actualDockerStdout := fixDepsDirRe.ReplaceAll(stdoutBuf.Bytes(), []byte("/tmp/luarocks_deps"))

			fixOutputRe := regexp.MustCompile(`genrockspec\d+`)
			actualDockerStdout = fixOutputRe.ReplaceAll(actualDockerStdout, []byte("genrockspec"))

			checkExpectedWithBytes(t, expectedStdout, actualDockerStdout)
		})
	}
}

func testAmalg(t *testing.T, testdataDir string, rt rockstype) {
	t.Helper()

	files, err := os.ReadDir(testdataDir)
	require.NoError(t, err)

	for _, test := range generateAmalgTests(files) {
		test := test
		t.Run(test.PrettyName(), func(t *testing.T) {
			t.Parallel()
			testOpts := buildTestOpts(t, testdataDir, rt, test)

			stdoutBytes := execDockerCommand(t, testOpts.amalgArgs...)
			checkExpectedWithBytes(t, testOpts.expectedStdout, stdoutBytes)
			checkExpectedWithFile(t, testOpts.expectedLua, testOpts.outLuaFileName)
			checkExpectedDirWithZippedFile(t, testOpts.expectedVendor, testOpts.vendorFileName)

			stdoutBytes = execDockerCommand(t, testOpts.luaExecArgs...)
			checkExpectedWithBytes(t, testOpts.expectedLuaExec, stdoutBytes)
		})
	}
}

type amalgtest struct {
	name    string
	isolate bool
	nodebug bool
}

func (t amalgtest) PrettyName() string {
	name := t.name
	if t.isolate {
		name += "_isolated"
	}
	if t.nodebug {
		name += "_nodebug"
	}

	return name
}

func generateAmalgTests(files []fs.DirEntry) []amalgtest {
	var tests []amalgtest
	for _, fi := range files {
		for _, nodebug := range []bool{false, true} {
			for _, isolate := range []bool{false, true} {
				tests = append(tests, amalgtest{
					name:    fi.Name(),
					isolate: isolate,
					nodebug: nodebug,
				})
			}
		}
	}

	return tests
}

type testOpts struct {
	outLuaFileName   string
	vendorFileName   string
	amalgArgs        []string
	luaExecArgs      []string
	expectedStdout   string
	expectedLua      string
	expectedVendor   string
	expectedLuaExec  string
	luaPath          string
	depsFileName     string
	rockspecFileName string
	disableDebug     bool
}

//nolint:funlen // setup a large number of fields
func buildTestOpts(
	t *testing.T, testdataDir string, rt rockstype, test amalgtest,
) testOpts {
	t.Helper()

	o := out{lua: "out.lua", stdout: "stdout"}
	if test.isolate {
		o.SetOutPrefix("isolated")
	}
	if test.nodebug {
		o.SetOutPrefix("nodebug")
	}

	testdataPath := filepath.Join(testdataDir, test.name)

	outLuaFile, err := os.CreateTemp(testdataPath, "out_*.lua")
	require.NoError(t, err)

	t.Cleanup(func() { os.Remove(outLuaFile.Name()) })
	require.NoError(t, outLuaFile.Close())

	vendorFile, err := os.CreateTemp(testdataPath, "vendor_*.zip")
	require.NoError(t, err)

	t.Cleanup(func() { os.Remove(vendorFile.Name()) })
	require.NoError(t, vendorFile.Close())

	if rt == vendoredRocks {
		vendorInPath := filepath.Join(testdataPath, "vendor_in")
		require.NoError(t, archive.ZipDirToFile(vendorInPath, vendorFile.Name()))
	}

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
	amalgArgs = append(amalgArgs, "enapter/rockamalg", "amalg",
		"-output", outLuaFile.Name(), "-vendor", vendorFile.Name())

	depsFileName := filepath.Join(testdataPath, "deps")
	if isExist(t, depsFileName) {
		amalgArgs = append(amalgArgs, "-d", depsFileName)
	} else {
		depsFileName = ""
	}

	rockspecFileName := filepath.Join(testdataPath, test.name+"-dev-1.rockspec")
	if isExist(t, rockspecFileName) {
		amalgArgs = append(amalgArgs, "-r", rockspecFileName)
	} else {
		rockspecFileName = ""
	}

	if test.isolate {
		amalgArgs = append(amalgArgs, "-i")
	}

	if test.nodebug {
		amalgArgs = append(amalgArgs, "--disable-debug")
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
		vendorFileName:   vendorFile.Name(),
		expectedStdout:   filepath.Join(testdataPath, o.stdout),
		expectedLua:      exepctedLuaFileName,
		expectedLuaExec:  filepath.Join(testdataPath, "out.lua.exec"),
		expectedVendor:   filepath.Join(testdataPath, "vendor"),
		luaPath:          filepath.Join(testdataPath, luaName),
		depsFileName:     depsFileName,
		rockspecFileName: rockspecFileName,
		disableDebug:     test.nodebug,
	}
}

type out struct {
	lua    string
	stdout string
}

func (o *out) SetOutPrefix(prefix string) {
	o.lua = prefix + "." + o.lua
	o.stdout = prefix + "." + o.stdout
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

func checkExpectedDirWithZippedFile(t *testing.T, expectedDirName, actualZipFileName string) {
	t.Helper()

	if update {
		require.NoError(t, os.RemoveAll(expectedDirName))
		if !fileIsEmpty(t, actualZipFileName) {
			require.NoError(t, archive.UnzipFileToDir(actualZipFileName, expectedDirName))
		}
	} else {
		if fileIsEmpty(t, actualZipFileName) {
			require.False(t, isExist(t, expectedDirName), "empty vendor.zip, but expected")
			return
		}

		expected := dirToFilesMap(t, expectedDirName)
		actual, err := archive.UnzipFileToFilesMap(actualZipFileName)
		require.NoError(t, err)

		require.Equal(t, expected, actual)
		if !reflect.DeepEqual(expected, actual) {
			require.Fail(t, "vendor differs — run test with update to see differences")
		}
	}
}

func checkExpectedDirWithZippedBytes(t *testing.T, expectedDirName string, zipBytes []byte) {
	t.Helper()

	if update {
		require.NoError(t, os.RemoveAll(expectedDirName))
		if len(zipBytes) != 0 {
			require.NoError(t, archive.UnzipBytesToDir(zipBytes, expectedDirName))
		}
	} else {
		if len(zipBytes) == 0 {
			require.False(t, isExist(t, expectedDirName), "empty vendor, but expected")
			return
		}

		expected := dirToFilesMap(t, expectedDirName)
		actual, err := archive.UnzipBytesToFilesMap(zipBytes)
		require.NoError(t, err)

		require.Equal(t, expected, actual)
		if !reflect.DeepEqual(expected, actual) {
			require.Fail(t, "vendor differs — run test with update to see differences")
		}
	}
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

func dirToFilesMap(t *testing.T, path string) map[string][]byte {
	t.Helper()

	files := make(map[string][]byte)
	fsys := os.DirFS(path)
	err := fs.WalkDir(fsys, ".", func(path string, entry fs.DirEntry, err error) error {
		if err != nil {
			return err
		}
		if entry.IsDir() {
			return nil
		}

		file, err := fsys.Open(path)
		if err != nil {
			return fmt.Errorf("open file %q: %w", path, err)
		}

		data, err := io.ReadAll(file)
		if err != nil {
			return fmt.Errorf("read file %q: %w", path, err)
		}
		files[path] = data
		return nil
	})
	require.NoError(t, err)
	return files
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

func fileIsEmpty(t *testing.T, path string) bool {
	t.Helper()

	fi, err := os.Stat(path)
	if err == nil {
		return fi.Size() == 0
	}

	if !os.IsNotExist(err) {
		t.Fatalf("stat finished with error: %v", err)
	}

	return false
}
