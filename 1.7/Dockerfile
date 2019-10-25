FROM ubuntu:bionic

MAINTAINER Dinko Korunic <dkorunic@haproxy.com>

LABEL Name HAProxy OSS
LABEL Release OSS Edition
LABEL Vendor HAProxy
LABEL Version 1.7.12
LABEL RUN /usr/bin/docker -d IMAGE

ENV HAPROXY_BRANCH 1.7
ENV HAPROXY_MINOR 1.7.12
ENV HAPROXY_SHA256 4118178b553a107b227f3f84774c7a50ae0b3ac2be39211c3db511ed4efe48ce
ENV HAPROXY_SRC_URL http://www.haproxy.org/download

ENV HAPROXY_UID haproxy
ENV HAPROXY_GID haproxy

RUN apt-get update && \
    apt-get install -y --no-install-recommends libssl1.0.0 zlib1g "libpcre2-*" liblua5.3-0 tar curl socat && \
    apt-get install -y --no-install-recommends gcc make libc6-dev libssl-dev libpcre3-dev zlib1g-dev liblua5.3-dev && \
    curl -sfSL "$HAPROXY_SRC_URL/$HAPROXY_BRANCH/src/haproxy-$HAPROXY_MINOR.tar.gz" -o haproxy.tar.gz && \
    echo "$HAPROXY_SHA256 *haproxy.tar.gz" | sha256sum -c - && \
    groupadd "$HAPROXY_GID" && \
    useradd -g "$HAPROXY_GID" "$HAPROXY_UID" && \
    mkdir -p /tmp/haproxy && \
    tar -xzf haproxy.tar.gz -C /tmp/haproxy --strip-components=1 && \
    rm -f haproxy.tar.gz && \
    make -C /tmp/haproxy -j"$(nproc)" TARGET=linux2628 CPU=generic USE_PCRE2=1 USE_PCRE2_JIT=1 USE_REGPARM=1 USE_OPENSSL=1 \
                            USE_ZLIB=1 USE_TFO=1 USE_LINUX_TPROXY=1 USE_LUA=1 USE_GETADDRINFO=1 \
                            all && \
    make -C /tmp/haproxy TARGET=linux2628 install-bin install-man && \
    ln -s /usr/local/sbin/haproxy /usr/sbin/haproxy && \
    mkdir -p /var/lib/haproxy && \
    chown "$HAPROXY_UID:$HAPROXY_GID" /var/lib/haproxy && \
    mkdir -p /usr/local/etc/haproxy && \
    ln -s /usr/local/etc/haproxy /etc/haproxy && \
    cp -R /tmp/haproxy/examples/errorfiles /usr/local/etc/haproxy/errors && \
    rm -rf /tmp/haproxy && \
    apt-get purge -y --auto-remove gcc make libc6-dev libssl-dev libpcre2-dev zlib1g-dev liblua5.3-dev && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

COPY haproxy.cfg /usr/local/etc/haproxy
COPY docker-entrypoint.sh /

STOPSIGNAL SIGUSR1

ENTRYPOINT ["/docker-entrypoint.sh"]
CMD ["haproxy", "-f", "/usr/local/etc/haproxy/haproxy.cfg"]
