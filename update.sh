#!/bin/bash
set -e

if test -z "$1"; then
	echo "Missing branch as first argument"
	exit 1
fi

if ! test -d "$1"; then
	echo "Cannot find $1 dedicated directory"
	exit 1
fi

cd "$1"

HAPROXY_BRANCH="$1"
DOCKERFILE="Dockerfile"
HAPROXY_SRC_URL="http://www.haproxy.org/download"
DATAPLANE_URL="https://github.com/haproxytech/dataplaneapi/releases/download"

if ! test -f "$DOCKERFILE"; then
	echo "Cannot find $DOCKERFILE"
	exit 1
fi

HAPROXY_MINOR=$(curl -sfSL "${HAPROXY_SRC_URL}/${HAPROXY_BRANCH}/src/" 2>/dev/null | \
    grep -o "<a href=\"haproxy-${HAPROXY_BRANCH}.*\.tar\.gz\">" | \
    sed -r -e 's!.*"haproxy-([^"/]+)\.tar\.gz".*!\1!' | sort -r -V | head -1)
HAPROXY_SHA256=$(curl -sfSL "${HAPROXY_SRC_URL}/${HAPROXY_BRANCH}/src/haproxy-${HAPROXY_MINOR}.tar.gz.sha256" 2>/dev/null | \
    awk '{print $1}')

if [ -z "${HAPROXY_MINOR}" ]; then
    HAPROXY_MINOR=$(curl -sfSL "${HAPROXY_SRC_URL}/${HAPROXY_BRANCH}/src/devel/" 2>/dev/null | \
        grep -o "<a href=\"haproxy-${HAPROXY_BRANCH}.*\.tar\.gz\">" | \
        sed -r -e 's!.*"haproxy-([^"/]+)\.tar\.gz".*!\1!' | sort -r -V | head -1)
    HAPROXY_SHA256=$(curl -sfSL "${HAPROXY_SRC_URL}/${HAPROXY_BRANCH}/src/devel/haproxy-${HAPROXY_MINOR}.tar.gz.sha256" | \
        awk '{print $1}')
fi

if [ -z "${HAPROXY_MINOR}" ]; then
    echo "Could not identify latest HAProxy release for ${HAPROXY_BRANCH} branch"
    exit 1
fi

if [ -z "HAPROXY_SHA256" ]; then
    echo "Could not get SHA256 for HAProxy release ${HAPROXY_MINOR}"
    exit 1
fi

DATAPLANE_SRC_URL="https://api.github.com/repos/haproxytech/dataplaneapi/releases/latest"
DATAPLANE_MINOR=$(curl -sfSL "$DATAPLANE_SRC_URL" | \
    grep '"tag_name":' | \
    sed -E 's/.*"v?([^"]+)".*/\1/')

if [ -z "${DATAPLANE_MINOR}" ]; then
    echo "Could not identify latest HAProxy Dataplane release"
    exit 1
fi

DATAPLANE_SHA_URL="https://github.com/haproxytech/dataplaneapi/releases/download/v${DATAPLANE_MINOR}/checksums.txt"
DATAPLANE_SHA256=$(curl -sfSL "$DATAPLANE_SHA_URL" | awk "/dataplaneapi_${DATAPLANE_MINOR}_Linux_x86_64.tar.gz/ {print \$1}")

if [ -z "${DATAPLANE_SHA256}" ]; then
    echo "Could not get SHA256 for HAProxy Dataplane release ${DATAPLANE_MINOR}"
    exit 1
fi

sed -r -i -e "s!^(ENV HAPROXY_SRC_URL) .*!\1 ${HAPROXY_SRC_URL}!;
            s!^(ENV HAPROXY_BRANCH) .*!\1 ${HAPROXY_BRANCH}!;
            s!^(ENV HAPROXY_MINOR) .*!\1 ${HAPROXY_MINOR}!;
            s!^(LABEL Version) .*!\1 ${HAPROXY_MINOR}!;
            s!^(ENV HAPROXY_SHA256) .*!\1 ${HAPROXY_SHA256}!
            s!^(ENV DATAPLANE_URL) .*!\1 ${DATAPLANE_URL}!;
            s!^(ENV DATAPLANE_MINOR) .*!\1 ${DATAPLANE_MINOR}!;
            s!^(ENV DATAPLANE_SHA256) .*!\1 ${DATAPLANE_SHA256}!" \
            "$DOCKERFILE"
