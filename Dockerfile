FROM golang:1.16-alpine3.15 as builder

RUN apk add --no-cache git bash

WORKDIR /app
COPY . .
RUN ./build.sh

FROM alpine:3.15

WORKDIR /app

RUN apk add --no-cache \
        bash build-base lua5.3 lua5.3-dev openssl \
        wget unzip zlib=1.2.12-r3 git

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
