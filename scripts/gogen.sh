#!/bin/sh

script_dir="$(cd "$(dirname "$0")" && pwd)"
project_dir=${script_dir%/*}

docker run --rm -v "$project_dir":/app -w /app kulti/gogrpc:go-1.16-1 "$@"
