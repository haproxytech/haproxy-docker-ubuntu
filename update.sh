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
HAPROXY_SRC_URL="https://www.haproxy.org/download"
# Retry transient errors and never hang: a failed lookup skips the branch
CURL=(curl -sfSL --retry 3 --retry-all-errors --connect-timeout 15 --max-time 60)

if ! test -f "$DOCKERFILE"; then
	echo "Cannot find $DOCKERFILE"
	exit 1
fi

DATAPLANE_MINOR_OLD=$(awk '/^ENV DATAPLANE_MINOR/ {print $NF; exit}' "$DOCKERFILE")
DATAPLANE_CHECKSUMS_SHA256_OLD=$(awk '/^ENV DATAPLANE_CHECKSUMS_SHA256/ {print $NF; exit}' "$DOCKERFILE")

# Fetch listings separately so that set -e aborts on download errors: a failed
# stable listing must not fall through to devel/, which still holds stale -dev
# releases for stable branches
HAPROXY_SRC_DIR="src"
HAPROXY_SRC_LIST=$("${CURL[@]}" "${HAPROXY_SRC_URL}/${HAPROXY_BRANCH}/${HAPROXY_SRC_DIR}/")
HAPROXY_MINOR=$(echo "${HAPROXY_SRC_LIST}" | \
    grep -o "<a href=\"haproxy-${HAPROXY_BRANCH}.*\.tar\.gz\">" | \
    sed -r -e 's!.*"haproxy-([^"/]+)\.tar\.gz".*!\1!' | sort -r -V | head -1)

if [ -z "${HAPROXY_MINOR}" ]; then
    HAPROXY_SRC_DIR="src/devel"
    HAPROXY_SRC_LIST=$("${CURL[@]}" "${HAPROXY_SRC_URL}/${HAPROXY_BRANCH}/${HAPROXY_SRC_DIR}/")
    HAPROXY_MINOR=$(echo "${HAPROXY_SRC_LIST}" | \
        grep -o "<a href=\"haproxy-${HAPROXY_BRANCH}.*\.tar\.gz\">" | \
        sed -r -e 's!.*"haproxy-([^"/]+)\.tar\.gz".*!\1!' | sort -r -V | head -1)
fi

if [ -z "${HAPROXY_MINOR}" ]; then
    echo "Could not identify latest HAProxy release for ${HAPROXY_BRANCH} branch"
    exit 1
fi

HAPROXY_SHA256=$("${CURL[@]}" "${HAPROXY_SRC_URL}/${HAPROXY_BRANCH}/${HAPROXY_SRC_DIR}/haproxy-${HAPROXY_MINOR}.tar.gz.sha256" | \
    awk '{print $1}')

if [ -z "${HAPROXY_SHA256}" ]; then
    echo "Could not get SHA256 for HAProxy release ${HAPROXY_MINOR}"
    exit 1
fi

GITHUB_AUTH=()
if [ -n "${GH_TOKEN}" ]; then
    GITHUB_AUTH=(-H "Authorization: Bearer ${GH_TOKEN}")
fi

DATAPLANE_SRC_URL="https://api.github.com/repos/haproxytech/dataplaneapi/releases?per_page=100"
DATAPLANE_SRC_URL_CONTENT=$("${CURL[@]}" "${GITHUB_AUTH[@]}" "${DATAPLANE_SRC_URL}")
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

# Fall back to the highest stable version: /releases/latest returns the most
# recently published release, which can be a v2.x maintenance release.
# Only for branches without a Dataplane API line of their own (2.x, or a new
# branch before its first Dataplane API release): a branch already on its own
# line must not silently switch to another one
if [ -z "${DATAPLANE_MINOR}" ]; then
    case "${DATAPLANE_MINOR_OLD}" in
        "${DATAPLANE_BRANCH}".*)
            echo "No Dataplane API ${DATAPLANE_BRANCH}.x release found, refusing to switch from ${DATAPLANE_MINOR_OLD}"
            exit 1
            ;;
    esac
    DATAPLANE_MINOR=$(echo "${DATAPLANE_SRC_URL_CONTENT}" | \
        grep -E '"tag_name": *"v[0-9]+\.[0-9]+\.[0-9]+"' | \
        sed -E 's/.*"v?([^"]+)".*/\1/' | \
        sort -V | \
        tail -1
    )
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

# Pin the release's checksums.txt: the Dockerfile verifies it against this
# hash and the downloaded tarball against it. Only for Dockerfiles that
# download a prebuilt Dataplane API; 2.x images build it from source
DATAPLANE_CHECKSUMS_SHA256=""
if grep -q "^ENV DATAPLANE_CHECKSUMS_SHA256" "${DOCKERFILE}"; then
    DATAPLANE_CHECKSUMS_FILE=$(mktemp)
    trap 'rm -f "${DATAPLANE_CHECKSUMS_FILE}"' EXIT
    "${CURL[@]}" -o "${DATAPLANE_CHECKSUMS_FILE}" \
        "https://github.com/haproxytech/dataplaneapi/releases/download/v${DATAPLANE_MINOR}/checksums.txt"
    DATAPLANE_CHECKSUMS_SHA256=$(sha256sum "${DATAPLANE_CHECKSUMS_FILE}" | awk '{print $1}')

    # A release's files never change once published; a different hash for an
    # already pinned version means they were replaced
    if [ "${DATAPLANE_MINOR}" = "${DATAPLANE_MINOR_OLD}" ] && \
       [ -n "${DATAPLANE_CHECKSUMS_SHA256_OLD}" ] && \
       [ "${DATAPLANE_CHECKSUMS_SHA256}" != "${DATAPLANE_CHECKSUMS_SHA256_OLD}" ]; then
        echo "checksums.txt of Dataplane API v${DATAPLANE_MINOR} changed since it was pinned, refusing to update"
        exit 1
    fi
fi

sed -r -i -e "s!^(ENV HAPROXY_SRC_URL) .*!\1 ${HAPROXY_SRC_URL}!;
            s!^(ENV HAPROXY_BRANCH) .*!\1 ${HAPROXY_BRANCH}!;
            s!^(ENV HAPROXY_MINOR) .*!\1 ${HAPROXY_MINOR}!;
            s!^(LABEL Version) .*!\1 ${HAPROXY_MINOR}!;
            s!^(ENV HAPROXY_SHA256) .*!\1 ${HAPROXY_SHA256}!
            s!^(ENV DATAPLANE_MINOR) .*!\1 ${DATAPLANE_MINOR}!
            s!^(ENV DATAPLANE_V2_MINOR) .*!\1 ${DATAPLANE_V2_MINOR}!
            s!^(ENV DATAPLANE_CHECKSUMS_SHA256) .*!\1 ${DATAPLANE_CHECKSUMS_SHA256}!" \
            "${DOCKERFILE}"

if [ -f "${DOCKERFILE_API}" ]; then
    sed -r -i -e "s!^(ENV HAPROXY_SRC_URL) .*!\1 ${HAPROXY_SRC_URL}!;
                s!^(ENV HAPROXY_BRANCH) .*!\1 ${HAPROXY_BRANCH}!;
                s!^(ENV HAPROXY_MINOR) .*!\1 ${HAPROXY_MINOR}!;
                s!^(LABEL Version) .*!\1 ${HAPROXY_MINOR}!;
                s!^(ENV HAPROXY_SHA256) .*!\1 ${HAPROXY_SHA256}!
                s!^(ENV DATAPLANE_MINOR) .*!\1 ${DATAPLANE_MINOR}!
                s!^(ENV DATAPLANE_V2_MINOR) .*!\1 ${DATAPLANE_V2_MINOR}!
                s!^(ENV DATAPLANE_CHECKSUMS_SHA256) .*!\1 ${DATAPLANE_CHECKSUMS_SHA256}!" \
                "${DOCKERFILE_API}"
fi
