FROM golang:1.25-alpine3.22 AS builder

RUN apk add --no-cache git bash

WORKDIR /app
COPY . .
RUN ./build.sh rockamalg
RUN ./build.sh healthcheck

FROM alpine:3.22

WORKDIR /app

RUN apk add --no-cache \
        bash build-base lua5.3 lua5.3-dev openssl \
        wget unzip zlib git

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
COPY --from=builder /app/bin/healthcheck /opt/tools/healthcheck
COPY pack_rocks.sh /opt/tools/pack_rocks.sh
RUN chmod +x /opt/tools/pack_rocks.sh

ENTRYPOINT ["/opt/rockamalg/rockamalg"]
HEALTHCHECK --interval=1s CMD /opt/tools/healthcheck
