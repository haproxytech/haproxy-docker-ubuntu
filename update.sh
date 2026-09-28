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
DOCKERFILE_API="Dockerfile.api"
HAPROXY_SRC_URL="http://www.haproxy.org/download"

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

if [ -z "${HAPROXY_SHA256}" ]; then
    echo "Could not get SHA256 for HAProxy release ${HAPROXY_MINOR}"
    exit 1
fi

GITHUB_AUTH=()
if [ -n "${GH_TOKEN}" ]; then
    GITHUB_AUTH=(-H "Authorization: Bearer ${GH_TOKEN}")
fi

DATAPLANE_SRC_URL="https://api.github.com/repos/haproxytech/dataplaneapi/releases?per_page=100"
DATAPLANE_SRC_URL_CONTENT=$(curl -sfSL "${GITHUB_AUTH[@]}" "${DATAPLANE_SRC_URL}")
DATAPLANE_BRANCH="${HAPROXY_BRANCH}"

# HAProxy 2.x images ship the latest Dataplane API 3.x (plus v2 as dataplaneapi-v2),
# so skip matching old v2.x Dataplane releases against the HAProxy branch
DATAPLANE_MINOR=""
case "${DATAPLANE_BRANCH}" in
    2.*) ;;
    *)
        DATAPLANE_MINOR=$(echo "${DATAPLANE_SRC_URL_CONTENT}" | \
            grep "\"tag_name\":.*\"v${DATAPLANE_BRANCH}\." | \
            sed -E 's/.*"v?([^"]+)".*/\1/' | \
            sort -V | \
            tail -1
        )
        ;;
esac

if [ -z "${DATAPLANE_MINOR}" ]; then
    DATAPLANE_SRC_URL="https://api.github.com/repos/haproxytech/dataplaneapi/releases/latest"
    DATAPLANE_MINOR=$(curl -sfSL "${GITHUB_AUTH[@]}" "${DATAPLANE_SRC_URL}" | \
        grep '"tag_name":' | \
        sed -E 's/.*"v?([^"]+)".*/\1/')
fi

DATAPLANE_V2_MINOR=$(echo "${DATAPLANE_SRC_URL_CONTENT}" | \
    grep '"tag_name":.*"v2\.' | \
    sed -E 's/.*"v?([^"]+)".*/\1/' | \
    sort -V | \
    tail -1
)

if [ -z "${DATAPLANE_MINOR}" ]; then
    echo "Could not identify latest Dataplane API release for ${DATAPLANE_BRANCH} branch"
    exit 1
fi

if [ -z "${DATAPLANE_V2_MINOR}" ] && grep -q "^ENV DATAPLANE_V2_MINOR" "${DOCKERFILE}"; then
    echo "Could not identify latest Dataplane API v2 release"
    exit 1
fi

sed -r -i -e "s!^(ENV HAPROXY_SRC_URL) .*!\1 ${HAPROXY_SRC_URL}!;
            s!^(ENV HAPROXY_BRANCH) .*!\1 ${HAPROXY_BRANCH}!;
            s!^(ENV HAPROXY_MINOR) .*!\1 ${HAPROXY_MINOR}!;
            s!^(LABEL Version) .*!\1 ${HAPROXY_MINOR}!;
            s!^(ENV HAPROXY_SHA256) .*!\1 ${HAPROXY_SHA256}!
            s!^(ENV DATAPLANE_MINOR) .*!\1 ${DATAPLANE_MINOR}!
            s!^(ENV DATAPLANE_V2_MINOR) .*!\1 ${DATAPLANE_V2_MINOR}!" \
            "${DOCKERFILE}"

if [ -f "${DOCKERFILE_API}" ]; then
    sed -r -i -e "s!^(ENV HAPROXY_SRC_URL) .*!\1 ${HAPROXY_SRC_URL}!;
                s!^(ENV HAPROXY_BRANCH) .*!\1 ${HAPROXY_BRANCH}!;
                s!^(ENV HAPROXY_MINOR) .*!\1 ${HAPROXY_MINOR}!;
                s!^(LABEL Version) .*!\1 ${HAPROXY_MINOR}!;
                s!^(ENV HAPROXY_SHA256) .*!\1 ${HAPROXY_SHA256}!
                s!^(ENV DATAPLANE_MINOR) .*!\1 ${DATAPLANE_MINOR}!
                s!^(ENV DATAPLANE_V2_MINOR) .*!\1 ${DATAPLANE_V2_MINOR}!" \
                "${DOCKERFILE_API}"
fi
