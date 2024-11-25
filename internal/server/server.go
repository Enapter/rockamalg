package server

import (
	"bytes"
	"context"
	"errors"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"

	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"
	"google.golang.org/protobuf/types/known/emptypb"

	"github.com/enapter/rockamalg/internal/api/rockamalgrpc"
	"github.com/enapter/rockamalg/internal/archive"
	"github.com/enapter/rockamalg/internal/rockamalg"
)

const newFilePerm = 0o600

type Server struct {
	rockamalgrpc.UnimplementedRockamalgServer
	amalg *rockamalg.Rockamalg
}

func New(rockamalgParams rockamalg.Params) *Server {
	amalg := rockamalg.New(rockamalgParams)
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
	if errSt := s.validateAmalgRequest(req); errSt != nil {
		return nil, errSt.Err()
	}

	amalgDir, err := os.MkdirTemp("/tmp", "amalg")
	if err != nil {
		return nil, status.Errorf(codes.Internal, "create temporary directory: %v", err)
	}
	defer func() { os.RemoveAll(amalgDir) }()

	amalgParams, errSt := s.prepareAmalgParams(ctx, req, amalgDir)
	if errSt != nil {
		return nil, errSt.Err()
	}

	if err := s.amalg.Amalg(ctx, amalgParams); err != nil {
		return nil, status.Errorf(codes.Internal, "amalgamation: %v", err)
	}

	out, err := os.ReadFile(amalgParams.Output)
	if err != nil {
		return nil, status.Errorf(codes.Internal, "reading result output: %v", err)
	}

	vendor, err := os.ReadFile(amalgParams.Vendor)
	if err != nil {
		if !errors.Is(err, os.ErrNotExist) {
			return nil, status.Errorf(codes.Internal, "reading result vendor: %v", err)
		}
	}

	return &rockamalgrpc.AmalgResponse{Lua: out, Vendor: vendor}, nil
}

func (s *Server) validateAmalgRequest(req *rockamalgrpc.AmalgRequest) *status.Status {
	if len(req.GetLuaDir()) != 0 && len(req.GetLuaFile()) != 0 {
		return status.New(codes.InvalidArgument,
			"lua file and lua directory are not allowed simultaneously")
	}

	if len(req.GetLuaDir()) == 0 && len(req.GetLuaFile()) == 0 {
		return status.New(codes.InvalidArgument,
			"lua file or lua directory are not provided")
	}
	return nil
}

func (s *Server) prepareAmalgParams(
	ctx context.Context, req *rockamalgrpc.AmalgRequest, amalgDir string,
) (rockamalg.AmalgParams, *status.Status) {
	zero := rockamalg.AmalgParams{}

	amalgParams := rockamalg.AmalgParams{
		Output:       filepath.Join(amalgDir, "out.lua"),
		Vendor:       filepath.Join(amalgDir, "vendor.zip"),
		Isolate:      req.GetIsolate(),
		DisableDebug: req.GetDisableDebug(),
		AllowDevDeps: req.GetAllowDevDependencies(),
	}

	if len(req.GetDependencies()) != 0 {
		amalgParams.Dependencies = filepath.Join(amalgDir, "deps")
		if err := s.writeDependenciesFile(req.GetDependencies(), amalgParams.Dependencies); err != nil {
			return zero, status.Newf(codes.Internal, "create dependencies file: %v", err)
		}
	}

	amalgParams.Rockspec, err = s.writeRockspec(ctx, req.GetRockspec(), amalgDir)
	if err != nil {
		return zero, status.Newf(codes.Internal, "create rockspec file: %v", err)
	}

	if len(req.GetLuaFile()) != 0 {
		amalgParams.Lua = filepath.Join(amalgDir, "fw.lua")
		if err := os.WriteFile(amalgParams.Lua, req.GetLuaFile(), newFilePerm); err != nil {
			return zero, status.Newf(codes.Internal, "create lua file: %v", err)
		}
	} else {
		amalgParams.Lua = filepath.Join(amalgDir, "fw")
		if err := archive.UnzipBytesToDir(req.GetLuaDir(), amalgParams.Lua); err != nil {
			return zero, status.Newf(codes.Internal, "create lua dir: %v", err)
		}
	}

	return amalgParams, nil
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
