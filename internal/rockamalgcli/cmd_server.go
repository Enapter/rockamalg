package rockamalgcli

import (
	"fmt"
	"time"

	grpcserver "github.com/kulti/grpc-retry/server"
	"github.com/urfave/cli/v2"

	"github.com/enapter/rockamalg/internal/api/rockamalgrpc"
	"github.com/enapter/rockamalg/internal/rockamalg"
	"github.com/enapter/rockamalg/internal/server"
)

type cmdServer struct {
	listenAddress string
	retryTimeout  time.Duration
	rocksServer   string
	forceIsolate  bool
}

func buildCmdServer() *cli.Command {
	var cmd cmdServer

	return &cli.Command{
		Name:  "server",
		Usage: "Run gRPC server to amalgamate files by request.",
		Flags: []cli.Flag{
			&cli.StringFlag{
				Name:        "listen-address",
				Aliases:     []string{"l"},
				Usage:       "Listen address",
				EnvVars:     []string{"LISTEN_ADDRESS"},
				Destination: &cmd.listenAddress,
				Required:    true,
			},
			&cli.DurationFlag{
				Name:        "retry-timeout",
				Aliases:     []string{"r"},
				Usage:       "Timeout between server restars",
				EnvVars:     []string{"RETRY_TIMEOUT"},
				Destination: &cmd.retryTimeout,
				Required:    true,
			},
			&cli.StringFlag{
				Name:        "rocks-server",
				Aliases:     []string{"s"},
				Usage:       "Use custom rocks server",
				Destination: &cmd.rocksServer,
			},
			&cli.BoolFlag{
				Name:        "force-isolate",
				Usage:       "Force server to use only isolate mode for amalgamation.",
				Destination: &cmd.forceIsolate,
			},
		},
		Action: func(cliCtx *cli.Context) error {
			gsrv := grpcserver.New(grpcserver.Params{
				Address:      cmd.listenAddress,
				RetryTimeout: cmd.retryTimeout,
				OnRetryFn: func(err error) {
					fmt.Fprintf(cliCtx.App.Writer, "gRPC server restarting: %v\n", err)
				},
			})

			go func() {
				<-cliCtx.Done()
				fmt.Fprintln(cliCtx.App.Writer, "gRPC server stopping")
				gsrv.GracefulStop()
				fmt.Fprintln(cliCtx.App.Writer, "gRPC server stopped")
			}()

			fmt.Fprintf(cliCtx.App.Writer, "gRPC server starting at %s\n", cmd.listenAddress)

			srv := server.New(rockamalg.Params{RocksServer: cmd.rocksServer, ForceIsolate: cmd.forceIsolate})
			rockamalgrpc.RegisterRockamalgServer(gsrv, srv)
			gsrv.Run(cliCtx.Context)

			return nil
		},
	}
}
