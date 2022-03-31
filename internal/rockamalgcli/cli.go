package rockamalgcli

import "github.com/urfave/cli/v2"

func NewApp() *cli.App {
	app := cli.NewApp()

	app.Usage = "Enapter tools to amalgamate lua files."

	app.Commands = []*cli.Command{
		buildCmdAmalg(),
		buildCmdServer(),
	}

	return app
}
