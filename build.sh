#!/bin/bash

set -e

BUILD_COMMIT="$(git rev-parse --short HEAD)"
BUILD_VERSION="$(git describe --tags || echo dev)"

name=$1
if [ -z "$name" ]; then
    echo "missed binary name to build: rockamalg or healthcheck"
    exit 1
fi

ldflags="-X main.commit=${BUILD_COMMIT} -X main.version=${BUILD_VERSION}"

# link statically
ldflags+=" -extldflags=-static"

# disable debug info generation and symbol table
ldflags+=" -w -s"

go build \
    -mod=vendor \
    -ldflags="${ldflags}" \
    -o "./bin/${name}" "./cmd/${name}"
