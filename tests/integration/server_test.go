//go:build integration
// +build integration

package integration_test

import (
	"archive/zip"
	"bytes"
	"context"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/stretchr/testify/require"
	"google.golang.org/grpc"
	"google.golang.org/grpc/credentials/insecure"
	"google.golang.org/protobuf/types/known/emptypb"

	"github.com/enapter/rockamalg/internal/api/rockamalgrpc"
)

func TestServerPublicRocks(t *testing.T) {
	t.Parallel()

	const port = 9090
	testServer(t, "testdata/amalg", port, publicRocks)
}

func TestServerPrivateRocks(t *testing.T) {
	t.Parallel()

	const port = 9091
	testServer(t, "testdata/amalg-private", port, privateRocks)
}

func testServer(t *testing.T, testdataDir string, port int, rt rockstype) {
	t.Helper()

	files, err := os.ReadDir(testdataDir)
	require.NoError(t, err)

	cli := runServerAndConnect(t, port, rt)

	for _, fi := range files {
		fi := fi
		for _, isolate := range []bool{false, true} {
			isolate := isolate
			t.Run(fmt.Sprintf("%s isolate %v", fi.Name(), isolate), func(t *testing.T) {
				t.Parallel()
				testOpts := buildTestOpts(t, fi.Name(), testdataDir, isolate, rt)
				req := buildReq(t, testOpts, isolate)

				resp, err := cli.Amalg(context.Background(), req)
				require.NoError(t, err)

				checkExpectedWithBytes(t, testOpts.expectedLua, resp.GetLua())

				stdoutBytes := execDockerCommand(t, testOpts.luaExecArgs...)
				checkExpectedWithBytes(t, testOpts.expectedLuaExec, stdoutBytes)
			})
		}
	}
}

func buildReq(t *testing.T, opts testOpts, isolate bool) *rockamalgrpc.AmalgRequest {
	t.Helper()

	req := &rockamalgrpc.AmalgRequest{Isolate: isolate}

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

func runServerAndConnect(t *testing.T, port int, rt rockstype) rockamalgrpc.RockamalgClient {
	t.Helper()

	args := []string{"run", "--rm", "--pull", "never", "--detach", "-p", fmt.Sprintf("%d:9090", port)}
	if rt == privateRocks {
		curdir, err := os.Getwd()
		require.NoError(t, err)

		args = append(args,
			"-v", filepath.Join(curdir, "testdata/rocks")+":/opt/rocks",
		)
	}
	args = append(args, "enapter/rockamalg", "server", "-l", "0.0.0.0:9090", "-r", "1s")
	if rt == privateRocks {
		args = append(args, "--rocks-server", "/opt/rocks")
	}

	output := execDockerCommand(t, args...)
	containerID := strings.TrimSpace(string(output))
	t.Cleanup(func() {
		execDockerCommand(t, "stop", containerID)
	})
	t.Cleanup(func() {
		t.Logf("rockamalg logs: %s", execDockerCommand(t, "logs", containerID))
	})

	conn, err := grpc.Dial(
		fmt.Sprintf("127.0.0.1:%d", port),
		grpc.WithTransportCredentials(insecure.NewCredentials()),
	)
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
