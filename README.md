# Rockamalg
![CI](https://github.com/Enapter/rockamalg/workflows/publish/badge.svg)
[![Go Report Card](https://goreportcard.com/badge/github.com/Enapter/rockamalg)](https://goreportcard.com/report/github.com/Enapter/rockamalg)
[![License](https://img.shields.io/github/license/Enapter/rockamalg)](LICENSE)

Rockamalg amalgamates several Lua files with all their dependencies into a single Lua file.

It uses [LuaRocks](https://luarocks.org/) to install dependencies and [amalg.lua](https://github.com/siffiejoe/lua-amalg/) to amalgamate.

## Why?

[Enapter Blueprints](https://developers.enapter.com/docs/#blueprints) uses a single Lua file. But it can be complex to manage, and developers may want to split them into several modules or use existing modules. So we need a tool to combine multiple Lua modules into a single file.

## How to use

### Tutorial

Enapter has [an official tutorial](https://developers.enapter.com/docs/tutorial/lua-complex/introduction) about Rockamalg usage.

### Quick start

You can describe dependencies in rockspec format like this:
```
lua-string ~> 1.2
inspect ~> 3.1.2
beemovie
```

Note, that Lua version should not be specified and commas and quotes are omitted.

Save this into file (e.g. `deps`) and you can amalgamate your `ucm.lua` with all dependencies via command:
```
docker run --rm -it \
	   -v $(pwd):/app \
	   enapter/rockamalg \
	   amalg -o out.lua -d deps ucm.lua
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

After that you can amalgamate your `ucm.lua` with all dependencies via command:
```
docker run --rm -it \
	   -v $(pwd):/app \
	   enapter/rockamalg \
	   amalg -o out.lua -r my.rockspec ucm.lua
```

### Lua directory

You can split `ucm.lua` into multiple files and use Lua modules as usual. The only one requirement is that entrypoint should have name `main.lua`.

E.g. your scrpt is placed in `lua_dir`. So you can amalgamate your `ucm.lua` by the following command:
```
docker run --rm -it \
	   -v $(pwd):/app \
	   enapter/rockamalg \
	   amalg -o ucm.lua -d deps lua_dir
```
## Server mode

It's possible to run rockamalg in server mode. This mode is useful to integrate with another services, which works in separate Docker containers.

## Dependency caching

🚧 At now caching is not recommended to use. Run server with `--force-isolate` flag to completly disable it. The problem is caching is prevent for use new version. E.g. you have dependency `inspect >= 3.1` and amalgamate your script with 3.1 version. But if a new version of inspect will be released, the rockamalg will use cached 3.1 version to satisfy dependency.

Downloading dependencies for each amalgamation could take a lot of time. By default rockamalg uses dependency cache to speedup the amalgamation.

You need to mount a volume into `/opt/rockamalg/.cache` to reuse cache between runs.

Single run:

```
docker run --rm -it \
	   -v $(pwd):/app \
	   -v rockamalg-cache:/opt/rockamalg/.cache \
	   enapter/rockamalg \
	   amalg -o ucm.lua -d deps lua_dir
```

Server mode:

```
docker run --rm -d \
	   -p 9090:9090 \
	   -v rockamalg-cache:/opt/rockamalg/.cache \
	   enapter/rockamalg \
	   server -l 0.0.0.0:9090 -r 1s
```

### Known issues

Sometimes running result file can cause an error like:

```
lua: main.lua:5: module 'mymode' not found:
	no field package.preload['mymode']
	no file '/opt/homebrew/share/lua/5.3/mymode.lua'
	no file '/opt/homebrew/share/lua/5.3/mymode/init.lua'
	no file '/opt/homebrew/lib/lua/5.3/mymode.lua'
	no file '/opt/homebrew/lib/lua/5.3/mymode/init.lua'
	no file './mymode.lua'
	no file './mymode/init.lua'
	no file '/opt/homebrew/lib/lua/5.3/mymode.so'
	no file '/opt/homebrew/lib/lua/5.3/loadall.so'
	no file './mymode.so'
stack traceback:
	[C]: in function 'require'
	main.lua:5: in main chunk
	ucm.lua:11: in main chunk
	[C]: in ?
```

It means, that rockamalg failed to detect all required Lua modules. In that case run rockamalg in *isolate mode* using `-i` flag:

```
docker run --rm -it \
	   -v $(pwd):/app \
	   enapter/rockamalg \
	   amalg -i -o ucm.lua -d deps lua_dir
```

## Contributing
### Generate GRPC API
To generate GRPC API use the following command:
```
./scripts/gogen.sh go generate -v ./internal/api/rockamalgrpc/generate.go
```
### Pack test rocks
To pack rocks for integration tests use the `pack_rocks.sh` script:
```
docker run --rm \
	   -v $(pwd)/tests/integration/testdata/rocks:/opt/res \
	   --entrypoint /opt/tools/pack_rocks.sh \
	   enapter/rockamalg \
	   inspect@3.1.2
```
