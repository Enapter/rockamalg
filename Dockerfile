FROM golang:1.19-alpine3.17 as builder

RUN apk add --no-cache git bash

WORKDIR /app
COPY . .
RUN ./build.sh

FROM alpine:3.17

WORKDIR /app

RUN apk add --no-cache \
        bash build-base lua5.3 lua5.3-dev openssl \
        wget unzip zlib=1.2.13-r0 git

RUN wget https://luarocks.org/releases/luarocks-3.8.0.tar.gz && \
    tar zxpf luarocks-3.8.0.tar.gz && \
    cd luarocks-3.8.0 && \
    ./configure && \
    make && \
    make install && \
    cd - && \
    rm -rf luarocks*

RUN luarocks install amalg 0.8-1

RUN mkdir /opt/rockamalg
COPY --from=builder /app/bin/rockamalg /opt/rockamalg/rockamalg

RUN mkdir /opt/tools
COPY pack_rocks.sh /opt/tools/pack_rocks.sh
RUN chmod +x /opt/tools/pack_rocks.sh

ENTRYPOINT ["/opt/rockamalg/rockamalg"]
