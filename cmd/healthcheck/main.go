package main

import (
	"context"
	"fmt"
	"net"
	"os"
	"os/signal"
	"syscall"

	"google.golang.org/grpc"
	"google.golang.org/grpc/credentials/insecure"
	"google.golang.org/protobuf/types/known/emptypb"

	"github.com/enapter/rockamalg/internal/api/rockamalgrpc"
)

func main() {
	if err := run(); err != nil {
		fmt.Fprintf(os.Stderr, "Error: %s", err)
		os.Exit(1)
	}
}

func run() error {
	ctx, cancel := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer cancel()

	_, port, err := net.SplitHostPort(os.Getenv("LISTEN_ADDRESS"))
	if err != nil {
		return fmt.Errorf("invalid listen address: %w", err)
	}

	healthcheckHost := net.JoinHostPort("127.0.0.1", port)

	conn, err := grpc.NewClient(
		healthcheckHost,
		grpc.WithTransportCredentials(insecure.NewCredentials()))
	if err != nil {
		return fmt.Errorf("failed to setup connection: %w", err)
	}

	if _, err := rockamalgrpc.NewRockamalgClient(conn).Ping(ctx, &emptypb.Empty{}); err != nil {
		return fmt.Errorf("failed to ping server: %w", err)
	}

	return nil
}
