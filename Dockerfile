FROM alpine:3.15

RUN apk add --no-cache \
        bash build-base lua5.3 lua5.3-dev openssl \
        wget unzip

RUN wget https://luarocks.org/releases/luarocks-3.8.0.tar.gz && \
    tar zxpf luarocks-3.8.0.tar.gz && \
    cd luarocks-3.8.0 && \
    ./configure && \
    make && \
    make install && \
    cd - && \
    rm -rf luarocks*

RUN luarocks install amalg

RUN mkdir /opt/rockamalg
COPY rockamalg.sh /opt/rockamalg

WORKDIR /app

ENTRYPOINT ["/opt/rockamalg/rockamalg.sh"]
