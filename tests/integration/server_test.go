//go:build integration
// +build integration

package integration_test

import (
	"archive/zip"
	"bytes"
	"context"
	"io"
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"testing"
	"time"

	"github.com/stretchr/testify/require"
	"google.golang.org/grpc"
	"google.golang.org/grpc/credentials/insecure"
	"google.golang.org/protobuf/types/known/emptypb"

	"github.com/enapter/rockamalg/internal/api/rockamalgrpc"
)

func TestServer(t *testing.T) {
	t.Parallel()

	files, err := os.ReadDir("testdata/amalg")
	require.NoError(t, err)

	cli := runServerAndConnect(t)

	for _, fi := range files {
		fi := fi
		t.Run(fi.Name(), func(t *testing.T) {
			t.Parallel()

			testOpts := buildTestOpts(t, fi.Name())
			req := buildReq(t, testOpts)

			resp, err := cli.Amalg(context.Background(), req)
			require.NoError(t, err)

			respLua := filterTmp(resp.GetLua())
			checkExpectedWithBytes(t, testOpts.expectedLua, respLua)

			stdoutBytes := execDockerCommand(t, testOpts.luaExecArgs...)
			checkExpectedWithBytes(t, testOpts.expectedLuaExec, stdoutBytes)
		})
	}
}

func filterTmp(d []byte) []byte {
	return regexp.MustCompile(`/tmp/luarocks_deps_\d*`).ReplaceAll(d, []byte("/usr/local"))
}

func buildReq(t *testing.T, opts testOpts) *rockamalgrpc.AmalgRequest {
	t.Helper()

	req := &rockamalgrpc.AmalgRequest{}

	if isDirectory(t, opts.luaPath) {
		req.LuaDir = zipDir(t, opts.luaPath)
	} else {
		req.LuaFile = shouldReadFile(t, opts.luaPath)
	}

	if opts.rockspecFileName != "" {
		req.Rockspec = shouldReadFile(t, opts.rockspecFileName)
	}

	if opts.depsFileName != "" {
		req.Dependencies = readDependencies(t, opts.depsFileName)
	}

	return req
}

func runServerAndConnect(t *testing.T) rockamalgrpc.RockamalgClient {
	t.Helper()

	output := execDockerCommand(t, "run", "--rm", "--pull", "never", "--detach", "-p", "9090:9090",
		"enapter/rockamalg", "server", "-l", "0.0.0.0:9090", "-r", "1s")
	containerID := strings.TrimSpace(string(output))
	t.Cleanup(func() {
		execDockerCommand(t, "stop", containerID)
	})
	t.Cleanup(func() {
		t.Logf("rockamalg logs: %s", execDockerCommand(t, "logs", containerID))
	})

	conn, err := grpc.Dial("127.0.0.1:9090", grpc.WithTransportCredentials(insecure.NewCredentials()))
	require.NoError(t, err)

	cli := rockamalgrpc.NewRockamalgClient(conn)

	require.Eventually(t, func() bool {
		_, err := cli.Ping(context.Background(), &emptypb.Empty{})
		return err == nil
	}, 5*time.Second, time.Millisecond)

	return cli
}

func readDependencies(t *testing.T, path string) []string {
	t.Helper()

	depsBytes := bytes.Split(shouldReadFile(t, path), []byte{'\n'})

	var deps []string
	for _, d := range depsBytes {
		if len(d) != 0 {
			deps = append(deps, string(d))
		}
	}

	return deps
}

func shouldReadFile(t *testing.T, path string) []byte {
	t.Helper()
	data, err := os.ReadFile(path)
	require.NoError(t, err)
	return data
}

func isDirectory(t *testing.T, path string) bool {
	t.Helper()
	fileInfo, err := os.Stat(path)
	require.NoError(t, err)
	return fileInfo.IsDir()
}

func zipDir(t *testing.T, path string) []byte {
	t.Helper()

	buf := &bytes.Buffer{}
	myZip := zip.NewWriter(buf)

	err := filepath.Walk(path, func(filePath string, info os.FileInfo, err error) error {
		if err != nil {
			return err
		}
		if info.IsDir() {
			return nil
		}
		relPath := strings.TrimPrefix(filePath, path)
		relPath = strings.TrimPrefix(relPath, "/")
		zipFile, err := myZip.Create(relPath)
		if err != nil {
			return err
		}
		fsFile, err := os.Open(filePath)
		if err != nil {
			return err
		}
		_, err = io.Copy(zipFile, fsFile)
		if err != nil {
			return err
		}
		return nil
	})

	require.NoError(t, err)
	require.NoError(t, myZip.Close())

	return buf.Bytes()
}
