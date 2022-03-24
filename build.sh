#!/bin/bash

set -ex


BUILD_COMMIT="$(git rev-parse --short HEAD)"
BUILD_VERSION="$(git describe --tags || echo dev)"

ldflags="-X main.commit=${BUILD_COMMIT} -X main.version=${BUILD_VERSION}"

# link statically
ldflags+=" -extldflags=-static"

# disable debug info generation and symbol table
ldflags+=" -w -s"

go build \
    -mod=vendor \
    -ldflags="${ldflags}" \
    -o ./bin/rockamalg ./cmd/rockamalg
