FROM ubuntu:noble AS awslc-builder

ENV AWSLC_URL https://github.com/aws/aws-lc.git
ENV AWSLC_TAG v1.65.1

ENV DEBIAN_FRONTEND noninteractive

RUN apt-get update && \
    apt-get install -y --no-install-recommends build-essential ca-certificates git cmake ninja-build golang && \
    git clone --depth 1 --branch "${AWSLC_TAG}" "${AWSLC_URL}" /tmp/aws-lc && \
    mkdir /tmp/aws-lc/build && \
    cd /tmp/aws-lc/build && \
    cmake -G Ninja -DCMAKE_INSTALL_PREFIX=/opt/aws-lc -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=ON .. && \
    ninja install && \
    rm -rf /tmp/aws-lc

FROM ubuntu:noble AS hapce-builder

ENV HAPROXY_BRANCH 3.2
ENV HAPROXY_MINOR 3.2.9-rebuild
ENV HAPROXY_SHA256 e660d141b29019f4d198785b0834cc3e9c96efceeb807c2fff2fc935bd3354c2
ENV HAPROXY_SRC_URL http://www.haproxy.org/download

COPY --from=awslc-builder /opt/aws-lc /opt/aws-lc

ENV DEBIAN_FRONTEND noninteractive

RUN apt-get update && \
    apt-get install -y --no-install-recommends procps libssl3t64 zlib1g "libpcre2-*" liblua5.4-0 libatomic1 tar curl socat ca-certificates libjemalloc2 && \
    apt-get install -y --no-install-recommends gcc make libc6-dev libssl-dev libpcre3-dev zlib1g-dev liblua5.4-dev libjemalloc-dev && \
    c_rehash && \
    curl -sfSL "${HAPROXY_SRC_URL}/${HAPROXY_BRANCH}/src/haproxy-${HAPROXY_MINOR}.tar.gz" -o haproxy.tar.gz && \
    echo "$HAPROXY_SHA256 *haproxy.tar.gz" | sha256sum -c - && \
    mkdir -p /tmp/haproxy && \
    tar -xzf haproxy.tar.gz -C /tmp/haproxy --strip-components=1 && \
    rm -f haproxy.tar.gz && \
    make -C /tmp/haproxy -j"$(nproc)" TARGET=linux-glibc CPU=generic USE_PCRE2=1 USE_PCRE2_JIT=1 \
                            USE_TFO=1 USE_LINUX_TPROXY=1 USE_LUA=1 USE_GETADDRINFO=1 \
                            USE_PROMEX=1 USE_SLZ=1 \
                            USE_OPENSSL_AWSLC=1 USE_PTHREAD_EMULATION=1 \
                            SSL_INC=/opt/aws-lc/include SSL_LIB=/opt/aws-lc/lib USE_QUIC=1 \
                            LDFLAGS="-L/opt/aws-lc/lib -Wl,-rpath,/opt/aws-lc/lib" \
                            ADDLIB=-ljemalloc \
                            all && \
    make -C /tmp/haproxy TARGET=linux-glibc install-bin

FROM ubuntu:noble

MAINTAINER Dinko Korunic <dkorunic@haproxy.com>

LABEL Name HAProxy
LABEL Release Community Edition
LABEL Vendor HAProxy
LABEL Version 3.2.9
LABEL RUN /usr/bin/docker -d IMAGE

ENV HAPROXY_BRANCH 3.2
ENV HAPROXY_MINOR 3.2.9
ENV HAPROXY_SHA256 e660d141b29019f4d198785b0834cc3e9c96efceeb807c2fff2fc935bd3354c2
ENV HAPROXY_SRC_URL http://www.haproxy.org/download

ENV HAPROXY_UID haproxy
ENV HAPROXY_GID haproxy

ENV DATAPLANE_MINOR 3.2.7
ENV DATAPLANE_URL https://github.com/haproxytech/dataplaneapi/releases/download

ENV DEBIAN_FRONTEND noninteractive

ARG TARGETPLATFORM

COPY --from=awslc-builder /opt/aws-lc /opt/aws-lc
COPY --from=hapce-builder /usr/local/sbin/haproxy /usr/local/sbin/haproxy
COPY --from=hapce-builder /tmp/haproxy/examples/errorfiles/ /usr/local/etc/haproxy/errors

RUN apt-get update && \
    apt-get install -y --no-install-recommends procps libssl3t64 zlib1g "libpcre2-*" liblua5.4-0 libatomic1 tar curl socat ca-certificates libjemalloc2 && \
    c_rehash && \
    groupadd "$HAPROXY_GID" && \
    useradd -g "$HAPROXY_GID" "$HAPROXY_UID" && \
    chmod +x /usr/local/sbin/haproxy && \
    ln -s /usr/local/sbin/haproxy /usr/sbin/haproxy && \
    mkdir -p /var/lib/haproxy && \
    chown "$HAPROXY_UID:$HAPROXY_GID" /var/lib/haproxy && \
    mkdir -p /usr/local/etc/haproxy && \
    ln -s /usr/local/etc/haproxy /etc/haproxy && \
    case "${TARGETPLATFORM}" in \
        "linux/arm64")      API_ARCH=arm64      ;; \
        "linux/amd64")      API_ARCH=x86_64     ;; \
        "linux/arm/v6")     API_ARCH=arm        ;; \
        "linux/arm/v7")     API_ARCH=arm        ;; \
        *) echo "ARG TARGETPLATFORM undeclared" >&2 && exit 1 ;; \
    esac && \
    curl -sfSL "${DATAPLANE_URL}/v${DATAPLANE_MINOR}/dataplaneapi_${DATAPLANE_MINOR}_linux_${API_ARCH}.tar.gz" -o dataplaneapi.tar.gz && \
    mkdir -p /tmp/dataplaneapi && \
    tar -xzf dataplaneapi.tar.gz -C /tmp/dataplaneapi && \
    rm -f dataplaneapi.tar.gz && \
    cp /tmp/dataplaneapi/dataplaneapi /usr/local/bin/dataplaneapi && \
    chmod +x /usr/local/bin/dataplaneapi && \
    touch /usr/local/etc/haproxy/dataplaneapi.yml && \
    chown "$HAPROXY_UID:$HAPROXY_GID" /usr/local/etc/haproxy/dataplaneapi.yml && \
    mkdir -p /usr/local/var/lib/dataplaneapi && \
    chown "$HAPROXY_UID:$HAPROXY_GID" /usr/local/var/lib/dataplaneapi && \
    ln -s /usr/local/var/lib/dataplaneapi /var/lib/dataplaneapi && \
    rm -rf /tmp/dataplaneapi && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* && \
    echo "/opt/aws-lc/lib" > /etc/ld.so.conf.d/awslc.conf && \
    mkdir -p /opt/aws-lc/ssl && \
    rm -rf /opt/aws-lc/ssl/certs && \
    ln -s /etc/ssl/certs /opt/aws-lc/ssl/certs && \
    ldconfig

COPY haproxy.cfg /usr/local/etc/haproxy
COPY docker-entrypoint.sh /

STOPSIGNAL SIGUSR1

ENTRYPOINT ["/docker-entrypoint.sh"]
CMD ["haproxy", "-f", "/usr/local/etc/haproxy/haproxy.cfg"]
