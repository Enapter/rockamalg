package rockamalgcli

import (
	"fmt"
	"time"

	grpcserver "github.com/kulti/grpc-retry/server"
	"github.com/urfave/cli/v2"

	"github.com/enapter/rockamalg/internal/api/rockamalgrpc"
	"github.com/enapter/rockamalg/internal/server"
)

type cmdServer struct {
	listenAddress string
	retryTimeout  time.Duration
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

			rockamalgrpc.RegisterRockamalgServer(gsrv, server.New())
			gsrv.Run(cliCtx.Context)

			return nil
		},
	}
}
