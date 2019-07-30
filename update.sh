#!/bin/sh
set -e

HAPROXY_BRANCH=${1:-2.0}
DOCKERFILE=Dockerfile-$HAPROXY_BRANCH
HAPROXY_SRC_URL=http://www.haproxy.org/download

HAPROXY_MINOR=$(curl -sfSL "$HAPROXY_SRC_URL/$HAPROXY_BRANCH/src/" 2>/dev/null | \
    grep -o "<a href=\"haproxy-$HAPROXY_BRANCH.*\.tar\.gz\">" | \
    sed -r -e 's!.*"haproxy-([^"/]+)\.tar\.gz".*!\1!' | sort -r -V | head -1)
HAPROXY_SHA256=$(curl -sfSL "$HAPROXY_SRC_URL/$HAPROXY_BRANCH/src/haproxy-$HAPROXY_MINOR.tar.gz.sha256" 2>/dev/null | \
    awk '{print $1}')

if [ -z "$HAPROXY_MINOR" ]; then
    HAPROXY_MINOR=$(curl -sfSL "$HAPROXY_SRC_URL/$HAPROXY_BRANCH/src/devel/" 2>/dev/null | \
        grep -o "<a href=\"haproxy-$HAPROXY_BRANCH.*\.tar\.gz\">" | \
        sed -r -e 's!.*"haproxy-([^"/]+)\.tar\.gz".*!\1!' | sort -r -V | head -1)
    HAPROXY_SHA256=$(curl -sfSL "$HAPROXY_SRC_URL/$HAPROXY_BRANCH/src/devel/haproxy-$HAPROXY_MINOR.tar.gz.sha256" | \
        awk '{print $1}')
fi

if [ -z "$HAPROXY_MINOR" ]; then
    echo "Could not identify latest HAProxy release for $HAPROXY_BRANCH branch"
    exit 1
fi

sed -r -i -e "s!^(ENV HAPROXY_SRC_URL) .*!\1 $HAPROXY_SRC_URL!;
            s!^(ENV HAPROXY_BRANCH) .*!\1 $HAPROXY_BRANCH!;
            s!^(ENV HAPROXY_MINOR) .*!\1 $HAPROXY_MINOR!;
            s!^(LABEL Version) .*!\1 $HAPROXY_MINOR!;
            s!^(ENV HAPROXY_SHA256) .*!\1 $HAPROXY_SHA256!" "$DOCKERFILE"
