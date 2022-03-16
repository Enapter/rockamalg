# Rockamalg

Rockamalg amalgates lua files with all dependencies inside one lua file. It uses luarocks to install dependencies.

## How to use

### Docker image
```
docker run --rm -it -v $(pwd):/app docker.enapter.com/lua/rockamalg -o out.lua -r my.rockspec fwdir
```
