package server

import (
	"archive/zip"
	"bytes"
	"context"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"strings"

	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"
	"google.golang.org/protobuf/types/known/emptypb"

	"github.com/enapter/rockamalg/internal/api/rockamalgrpc"
	"github.com/enapter/rockamalg/internal/rockamalg"
)

const newFilePerm = 0o600

type Server struct {
	rockamalgrpc.UnimplementedRockamalgServer
	amalg *rockamalg.Rockamalg
}

func New() *Server {
	amalg := rockamalg.New()
	return &Server{
		amalg: amalg,
	}
}

func (s *Server) Ping(context.Context, *emptypb.Empty) (*emptypb.Empty, error) {
	return &emptypb.Empty{}, nil
}

func (s *Server) Amalg(
	ctx context.Context, req *rockamalgrpc.AmalgRequest,
) (*rockamalgrpc.AmalgResponse, error) {
	if len(req.GetFirmwareDir()) != 0 && len(req.GetFirmwareFile()) != 0 {
		return nil, status.Error(codes.InvalidArgument,
			"firmware file and firmware directory are not allowed simultaneously")
	}

	if len(req.GetFirmwareDir()) == 0 && len(req.GetFirmwareFile()) == 0 {
		return nil, status.Error(codes.InvalidArgument,
			"firmware file or firmware directory are not provided")
	}

	amalgDir, err := os.MkdirTemp("/tmp", "amalg")
	if err != nil {
		return nil, status.Errorf(codes.Internal, "create temporary directory: %v", err)
	}
	defer func() { os.RemoveAll(amalgDir) }()

	amalgParams := rockamalg.Params{
		Output:  filepath.Join(amalgDir, "out.lua"),
		Isolate: true,
	}

	if len(req.GetDependencies()) != 0 {
		amalgParams.Dependencies = filepath.Join(amalgDir, "deps")
		if err := s.writeDependenciesFile(req.GetDependencies(), amalgParams.Dependencies); err != nil {
			return nil, status.Errorf(codes.Internal, "create dependencies file: %v", err)
		}
	}

	amalgParams.Rockspec, err = s.writeRockspec(ctx, req.GetRockspec(), amalgDir)
	if err != nil {
		return nil, status.Errorf(codes.Internal, "create rockspec file: %v", err)
	}

	if len(req.GetFirmwareFile()) != 0 {
		amalgParams.Firmware = filepath.Join(amalgDir, "fw.lua")
		if err := os.WriteFile(amalgParams.Firmware, req.GetFirmwareFile(), newFilePerm); err != nil {
			return nil, status.Errorf(codes.Internal, "create firmware file: %v", err)
		}
	} else {
		amalgParams.Firmware = filepath.Join(amalgDir, "fw")
		if err := s.writeFirmwareDir(req.GetFirmwareDir(), amalgParams.Firmware); err != nil {
			return nil, status.Errorf(codes.Internal, "create firmware dir: %v", err)
		}
	}

	if err := s.amalg.Amalg(ctx, amalgParams); err != nil {
		return nil, status.Errorf(codes.Internal, "amalgamation: %v", err)
	}

	out, err := os.ReadFile(amalgParams.Output)
	if err != nil {
		return nil, status.Errorf(codes.Internal, "reading result output: %v", err)
	}

	return &rockamalgrpc.AmalgResponse{
		Lua: out,
	}, nil
}

func (s *Server) writeDependenciesFile(deps []string, path string) error {
	f, err := os.Create(path)
	if err != nil {
		return fmt.Errorf("create file: %w", err)
	}

	for _, d := range deps {
		if _, err := fmt.Fprintf(f, "%s\n", d); err != nil {
			return fmt.Errorf("write: %w", err)
		}
	}

	return nil
}

func (s *Server) writeRockspec(ctx context.Context, data []byte, path string) (string, error) {
	if len(data) == 0 {
		return "", nil
	}

	stdoutBuf := &bytes.Buffer{}
	stdinBuf := &bytes.Buffer{}
	stdinBuf.Write(data)
	stdinBuf.WriteString("\nprint(package)\nprint(version)\n")

	luacmd := exec.CommandContext(ctx, "lua5.3")
	luacmd.Stdout = stdoutBuf
	luacmd.Stdin = stdinBuf

	if err := luacmd.Run(); err != nil {
		return "", fmt.Errorf("parse rockspec: %w", err)
	}

	const epxectedOutputLines = 2
	luaout := strings.Split(stdoutBuf.String(), "\n")
	if len(luaout) < epxectedOutputLines {
		return "", errRockspecUnexpected
	}

	pkg, version := luaout[0], luaout[1]
	if pkg == "" || version == "" {
		return "", errRockspecPackageOrVersionMissed
	}

	rockspecFileName := filepath.Join(path, pkg+"-"+version+".rockspec")
	if err := os.WriteFile(rockspecFileName, data, newFilePerm); err != nil {
		return "", fmt.Errorf("write: %w", err)
	}

	return rockspecFileName, nil
}

func (s *Server) writeFirmwareDir(data []byte, path string) error {
	archive, err := zip.NewReader(bytes.NewReader(data), int64(len(data)))
	if err != nil {
		return fmt.Errorf("create zip reader: %w", err)
	}

	for _, f := range archive.File {
		if f.FileInfo().IsDir() {
			continue
		}

		filePath, err := sanitizeArchivePath(path, f.Name)
		if err != nil {
			return err
		}

		if err := os.MkdirAll(filepath.Dir(filePath), os.ModePerm); err != nil {
			return fmt.Errorf("create dir: %w", err)
		}

		dstFile, err := os.OpenFile(filePath, os.O_WRONLY|os.O_CREATE|os.O_TRUNC, f.Mode())
		if err != nil {
			return fmt.Errorf("create file: %w", err)
		}

		fileInArchive, err := f.Open()
		if err != nil {
			return fmt.Errorf("open archive file: %w", err)
		}

		//#nosec G110 -- this server for internal usage only.
		if _, err := io.Copy(dstFile, fileInArchive); err != nil {
			return fmt.Errorf("copy: %w", err)
		}

		dstFile.Close()
		fileInArchive.Close()
	}

	return nil
}

// sanitizeArchivePath protects archive file pathing from "G305: Zip Slip vulnerability"
// https://snyk.io/research/zip-slip-vulnerability#go
func sanitizeArchivePath(d, t string) (v string, err error) {
	v = filepath.Join(d, t)
	if strings.HasPrefix(v, filepath.Clean(d)) {
		return v, nil
	}

	return "", errZipInvalidFilePath
}
