# Rockamalg
![CI](https://github.com/Enapter/rockamalg/workflows/publish/badge.svg)
[![Go Report Card](https://goreportcard.com/badge/github.com/Enapter/rockamalg)](https://goreportcard.com/report/github.com/Enapter/rockamalg)
[![License](https://img.shields.io/github/license/Enapter/rockamalg)](LICENSE)

Rockamalg amalgamates several Lua files with all their dependencies into a single Lua file.

It uses [LuaRocks](https://luarocks.org/) to install dependencies and [amalg.lua](https://github.com/siffiejoe/lua-amalg/) to amalgamate.

## Why?

[Enapter Blueprints](https://developers.enapter.com/docs/#blueprints) uses firmware as a single Lua file. But it can be complex to manage, and firmware developers may want to split them into several modules or use existing modules. So we need a tool to combine multiple Lua modules into a single firmware file.

## How to use

### Tutorial

Enapter has [an official tutorial](https://developers.enapter.com/docs/tutorial/lua-complex/multi-file) about Rockamalg usage.

### Quick start

You can describe dependencies in rockspec format like this:
```
lua-string ~> 1.2
inspect ~> 3.1.2
beemovie
```

Note, that Lua version should not be specified and commas and quotes are omitted.

Save this into file (e.g. `deps`) and you can amalgamate your `firmware.lua` with all dependencies via command:
```
docker run --rm -it -v $(pwd):/app enapter/rockamalg amalg -o out.lua -d deps firmware.lua
```

### Rockspec

Or your can use rockspec if you have. It is used only for dependencies resolving. The minimal spec file looks like:
```
rockspec_format = '3.0'
package = 'generated'
version = 'dev-1'
source = {
  url = 'generated'
}
dependencies = {
  'lua ~> 5.3',
  'lua-string ~> 1.2',
  'inspect ~> 3.1.2',
  'beemovie'
}
```

This file should have a specific name `generated-dev-1.rockspec`. The parts of name should be the same as described inside specfile: `<package>-<version>.rockspec`.

After that you can amalgamate your `firmware.lua` with all dependencies via command:
```
docker run --rm -it -v $(pwd):/app enapter/rockamalg amalg -o out.lua -r my.rockspec firmware.lua
```

### Firmware directory

You can split `firmware.lua` into multiple files and use Lua modules as usual. The only one requirement is that entrypoint should have name `main.lua`.

E.g. your firmware is placed in `firmware_dir`. So you can amalgamate your firmware by the following command:
```
docker run --rm -it -v $(pwd):/app enapter/rockamalg amalg -o out.lua -d deps firmware_dir
```

## Server mode

It's possible to run rockamalg in server mode. This mode is useful to integrate with another services, which works in separate Docker containers.

## Contributing
### Generate GRPC API
To generate GRPC API use the following command:
```
./scripts/gogen.sh go generate -v ./internal/api/rockamalgrpc/generate.go
```
