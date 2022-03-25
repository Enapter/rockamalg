package server

import (
	"context"
	"errors"
	"fmt"
	"net"
	"sync/atomic"
	"time"

	"google.golang.org/grpc"
)

// Server is a wrapper for the grpc.Server which restarts after failures.
type Server struct {
	*grpc.Server
	p     Params
	ready int32
}

// Params contains listen and retry options.
// If Address is invalid it can cause a listen error and infinite retries.
// If RetryTimout is zero retris happen immediately.
// If OnRetryFn is nil it will not be called.
type Params struct {
	Address      string
	RetryTimeout time.Duration
	OnRetryFn    func(err error)
}

// New creates a new grpc.Server wrapper.
func New(params Params, grpcOpts ...grpc.ServerOption) *Server {
	return &Server{
		p:      params,
		Server: grpc.NewServer(grpcOpts...),
	}
}

// Run runs an infinite loop with listen and serve. It stops when ctx is done.
func (s *Server) Run(ctx context.Context) {
	for {
		if err := s.listenAndServe(); err != nil {
			if s.p.OnRetryFn != nil {
				s.p.OnRetryFn(err)
			}

			select {
			case <-ctx.Done():
				return
			case <-time.After(s.p.RetryTimeout):
				continue
			}
		}

		return
	}
}

// Ready returns true if the Server ready to accept connections.
func (s *Server) Ready() bool {
	return atomic.LoadInt32(&s.ready) == 1
}

func (s *Server) listenAndServe() error {
	listener, err := net.Listen("tcp", s.p.Address)
	if err != nil {
		return fmt.Errorf("listen: %w", err)
	}

	atomic.StoreInt32(&s.ready, 1)
	defer atomic.StoreInt32(&s.ready, 0)

	err = s.Serve(listener)
	if err != nil && !errors.Is(err, grpc.ErrServerStopped) {
		return fmt.Errorf("serve: %w", err)
	}

	return nil
}
