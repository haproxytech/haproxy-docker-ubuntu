FROM golang:alpine AS builder

ENV DATAPLANE_MINOR 3.2.6
ENV DATAPLANE_V2_MINOR 2.9.19
ENV DATAPLANE_URL https://github.com/haproxytech/dataplaneapi.git

RUN apk add --no-cache ca-certificates git make && \
    git clone "${DATAPLANE_URL}" "${GOPATH}/src/github.com/haproxytech/dataplaneapi" && \
    cd "${GOPATH}/src/github.com/haproxytech/dataplaneapi" && \
    git checkout "v${DATAPLANE_MINOR}" && \
    make build && cp build/dataplaneapi /dataplaneapi && \
    make clean && \
    git checkout "v${DATAPLANE_V2_MINOR}" && \
    make build && cp build/dataplaneapi /dataplaneapi-v2

FROM ubuntu:noble

MAINTAINER Dinko Korunic <dkorunic@haproxy.com>

LABEL Name HAProxy
LABEL Release Community Edition
LABEL Vendor HAProxy
LABEL Version 3.3-dev14
LABEL RUN /usr/bin/docker -d IMAGE

ENV HAPROXY_BRANCH 3.3
ENV HAPROXY_MINOR 3.3-dev14
ENV HAPROXY_SHA256 b2f22bc2266b980a486f7d9f1d205a218710d1e68140de44d7ab2ddfa321fa6c
ENV HAPROXY_SRC_URL http://www.haproxy.org/download

ENV HAPROXY_UID haproxy
ENV HAPROXY_GID haproxy

ENV DEBIAN_FRONTEND noninteractive

COPY --from=builder /dataplaneapi /usr/local/bin/dataplaneapi
COPY --from=builder /dataplaneapi-v2 /usr/local/bin/dataplaneapi-v2

RUN apt-get update && \
    apt-get install -y --no-install-recommends procps libssl3t64 zlib1g "libpcre2-*" liblua5.4-0 libatomic1 tar curl socat ca-certificates libjemalloc2 && \
    apt-get install -y --no-install-recommends gcc make libc6-dev libssl-dev libpcre3-dev zlib1g-dev liblua5.4-dev libjemalloc-dev && \
    curl -sfSL "${HAPROXY_SRC_URL}/${HAPROXY_BRANCH}/src/devel/haproxy-${HAPROXY_MINOR}.tar.gz" -o haproxy.tar.gz && \
    echo "$HAPROXY_SHA256 *haproxy.tar.gz" | sha256sum -c - && \
    groupadd "$HAPROXY_GID" && \
    useradd -g "$HAPROXY_GID" "$HAPROXY_UID" && \
    mkdir -p /tmp/haproxy && \
    tar -xzf haproxy.tar.gz -C /tmp/haproxy --strip-components=1 && \
    rm -f haproxy.tar.gz && \
    make -C /tmp/haproxy -j"$(nproc)" TARGET=linux-glibc CPU=generic USE_PCRE2=1 USE_PCRE2_JIT=1 \
                            USE_TFO=1 USE_LINUX_TPROXY=1 USE_LUA=1 USE_GETADDRINFO=1 \
                            USE_PROMEX=1 USE_SLZ=1 \
                            USE_OPENSSL=1 USE_PTHREAD_EMULATION=1 \
                            USE_QUIC=1 USE_QUIC_OPENSSL_COMPAT=1 \
                            ADDLIB=-ljemalloc \
                            all && \
    make -C /tmp/haproxy TARGET=linux-glibc install-bin install-man && \
    ln -s /usr/local/sbin/haproxy /usr/sbin/haproxy && \
    mkdir -p /var/lib/haproxy && \
    chown "$HAPROXY_UID:$HAPROXY_GID" /var/lib/haproxy && \
    mkdir -p /usr/local/etc/haproxy && \
    ln -s /usr/local/etc/haproxy /etc/haproxy && \
    cp -R /tmp/haproxy/examples/errorfiles /usr/local/etc/haproxy/errors && \
    rm -rf /tmp/haproxy && \
    apt-get purge -y --auto-remove gcc make libc6-dev libssl-dev libpcre2-dev zlib1g-dev liblua5.4-dev libjemalloc-dev && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* && \
    chmod +x /usr/local/bin/dataplaneapi && \
    ln -s /usr/local/bin/dataplaneapi /usr/bin/dataplaneapi && \
    chmod +x /usr/local/bin/dataplaneapi-v2 && \
    ln -s /usr/local/bin/dataplaneapi-v2 /usr/bin/dataplaneapi-v2 && \
    touch /usr/local/etc/haproxy/dataplaneapi.yml && \
    chown "$HAPROXY_UID:$HAPROXY_GID" /usr/local/etc/haproxy/dataplaneapi.yml

COPY haproxy.cfg /usr/local/etc/haproxy
COPY docker-entrypoint.sh /

STOPSIGNAL SIGUSR1

ENTRYPOINT ["/docker-entrypoint.sh"]
CMD ["haproxy", "-f", "/usr/local/etc/haproxy/haproxy.cfg"]
