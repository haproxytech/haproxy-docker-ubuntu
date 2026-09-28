#!/bin/bash
# Work out the image tags for BUILD_VER of BUILD_BRANCH and append them to
# $GITHUB_OUTPUT as "tags" (plain image) and "s6_tags" (s6 image).
#
# Branch and latest tags are only added when BUILD_VER is the newest release
# of its branch, so rebuilding or re-pushing an older release never moves them
# back. Latest tags are only added for the branch named in STABLE_BRANCH.
set -e

: "${BUILD_VER:?}" "${BUILD_BRANCH:?}" "${DOCKER_IMAGE:?}" "${DOCKER_IMAGE_UNIFIED:?}"
: "${UNIFIED_PREFIX:?}" "${GHCR_IMAGE:?}" "${GITHUB_OUTPUT:?}"

STABLE_BRANCH=$(cat STABLE_BRANCH)

# Fetch separately so that set -e aborts when the tag list cannot be read
REMOTE_TAGS=$(git ls-remote --tags --refs origin)
NEWEST=$( { echo "${REMOTE_TAGS}" | sed 's!.*refs/tags/!!' | \
    grep -E "^${BUILD_BRANCH//./\\.}([.-]|$)"; echo "${BUILD_VER}"; } | sort -V | tail -1)

SUFFIXES="${BUILD_VER}"
if [ "${NEWEST}" = "${BUILD_VER}" ]; then
    SUFFIXES="${SUFFIXES} ${BUILD_BRANCH}"
    if [ "${BUILD_BRANCH}" = "${STABLE_BRANCH}" ]; then
        SUFFIXES="${SUFFIXES} latest"
    fi
else
    echo "::notice::${BUILD_VER} is older than ${NEWEST}, not moving ${BUILD_BRANCH} or latest tags"
fi

emit() {
    local name="$1" prefix="$2" suffix
    echo "${name}<<EOF"
    for suffix in ${SUFFIXES}; do
        echo "${DOCKER_IMAGE}:${prefix}${suffix}"
        echo "${DOCKER_IMAGE_UNIFIED}:${UNIFIED_PREFIX}-${prefix}${suffix}"
        echo "${GHCR_IMAGE}:${prefix}${suffix}"
    done
    echo "EOF"
}

{
    emit tags ""
    emit s6_tags "s6-"
} >> "${GITHUB_OUTPUT}"
