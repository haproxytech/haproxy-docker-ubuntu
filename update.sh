#!/bin/bash
set -e

# Exit status when HAProxy was updated but Dataplane API or gopherd kept its
# current pin; build.sh still ships the HAProxy update and reports the rest.
# Every other failure exits with 1, whichever command failed: curl's own
# exit statuses include 100 too
UPDATE_PARTIAL=100
PARTIAL=""
TMP_DIR=""
on_exit() {
	local status=$?
	if [ -n "${TMP_DIR}" ]; then
		rm -rf "${TMP_DIR}"
	fi
	if [ "${status}" -ne 0 ] && [ -z "${PARTIAL}" ]; then
		exit 1
	fi
}
trap on_exit EXIT

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
# Branch number as a regex, with literal dots
HAPROXY_BRANCH_RE="${HAPROXY_BRANCH//./\\.}"

# Every value is checked before it is used in a URL, a git tag or the sed
# rewrite below: only shapes that the build workflow's tag filter accepts are
# built, and a stray "!" or ";" would otherwise end up as sed commands
require_format() {
	local name="$1" value="$2" regex="$3"
	if ! [[ "${value}" =~ ${regex} ]]; then
		echo "Unexpected ${name} '${value}', refusing to update"
		exit 1
	fi
}

require_format "branch" "${HAPROXY_BRANCH}" '^[0-9]+\.[0-9]+$'
DOCKERFILE="Dockerfile"
DOCKERFILE_API="Dockerfile.api"
HAPROXY_SRC_URL="https://www.haproxy.org/download"
# Retry transient errors and never hang: a failed HAProxy lookup fails the
# branch, a failed Dataplane API or gopherd lookup keeps that pin
CURL=(curl -sfSL --retry 3 --retry-all-errors --connect-timeout 15 --max-time 60)

if ! test -f "$DOCKERFILE"; then
	echo "Cannot find $DOCKERFILE"
	exit 1
fi

# Fetch listings separately so that set -e aborts on download errors: a failed
# stable listing must not fall through to devel/, which still holds stale -dev
# releases for stable branches
HAPROXY_SRC_DIR="src"
HAPROXY_SRC_LIST=$("${CURL[@]}" "${HAPROXY_SRC_URL}/${HAPROXY_BRANCH}/${HAPROXY_SRC_DIR}/")
HAPROXY_MINOR=$(echo "${HAPROXY_SRC_LIST}" |
	grep -oE "<a href=\"haproxy-${HAPROXY_BRANCH_RE}(\.[0-9]+|-dev[0-9]+)\.tar\.gz\">" |
	sed -r -e 's!.*"haproxy-([^"/]+)\.tar\.gz".*!\1!' | sort -r -V | head -1)

if [ -z "${HAPROXY_MINOR}" ]; then
	HAPROXY_SRC_DIR="src/devel"
	HAPROXY_SRC_LIST=$("${CURL[@]}" "${HAPROXY_SRC_URL}/${HAPROXY_BRANCH}/${HAPROXY_SRC_DIR}/")
	HAPROXY_MINOR=$(echo "${HAPROXY_SRC_LIST}" |
		grep -oE "<a href=\"haproxy-${HAPROXY_BRANCH_RE}(\.[0-9]+|-dev[0-9]+)\.tar\.gz\">" |
		sed -r -e 's!.*"haproxy-([^"/]+)\.tar\.gz".*!\1!' | sort -r -V | head -1)
fi

if [ -z "${HAPROXY_MINOR}" ]; then
	echo "Could not identify latest HAProxy release for ${HAPROXY_BRANCH} branch"
	exit 1
fi
require_format "HAProxy version" "${HAPROXY_MINOR}" "^${HAPROXY_BRANCH_RE}(\.[0-9]+|-dev[0-9]+)\$"

HAPROXY_SHA256=$("${CURL[@]}" "${HAPROXY_SRC_URL}/${HAPROXY_BRANCH}/${HAPROXY_SRC_DIR}/haproxy-${HAPROXY_MINOR}.tar.gz.sha256" |
	awk '{print $1}')

if [ -z "${HAPROXY_SHA256}" ]; then
	echo "Could not get SHA256 for HAProxy release ${HAPROXY_MINOR}"
	exit 1
fi
require_format "HAProxy SHA256" "${HAPROXY_SHA256}" '^[0-9a-f]{64}$'

TMP_DIR=$(mktemp -d)

# The tarball has to match its published SHA256 before that gets pinned, also
# when haproxy.org replaced the tarball of the pinned version. An unchanged
# pin already matched when it was pinned
HAPROXY_MINOR_OLD=$(awk '/^ENV HAPROXY_MINOR/ {print $NF; exit}' "${DOCKERFILE}")
HAPROXY_SHA256_OLD=$(awk '/^ENV HAPROXY_SHA256/ {print $NF; exit}' "${DOCKERFILE}")
if [ "${HAPROXY_MINOR}" != "${HAPROXY_MINOR_OLD}" ] || [ "${HAPROXY_SHA256}" != "${HAPROXY_SHA256_OLD}" ]; then
	"${CURL[@]}" --max-time 300 -o "${TMP_DIR}/haproxy.tar.gz" \
		"${HAPROXY_SRC_URL}/${HAPROXY_BRANCH}/${HAPROXY_SRC_DIR}/haproxy-${HAPROXY_MINOR}.tar.gz"
	if ! echo "${HAPROXY_SHA256}  ${TMP_DIR}/haproxy.tar.gz" | sha256sum -c --status -; then
		echo "HAProxy ${HAPROXY_MINOR} tarball does not match its published SHA256, refusing to update"
		exit 1
	fi
	if [ "${HAPROXY_MINOR}" = "${HAPROXY_MINOR_OLD}" ]; then
		echo "HAProxy ${HAPROXY_MINOR} tarball changed since it was pinned, pinning the new one: it matches its SHA256"
	fi
fi

GITHUB_AUTH=()
if [ -n "${GH_TOKEN}" ]; then
	GITHUB_AUTH=(-H "Authorization: Bearer ${GH_TOKEN}")
fi

# Apply the sed expressions $@ to the Dockerfile and, when there is one, to
# the Dockerfile.api
rewrite() {
	sed -r -i "$@" "${DOCKERFILE}"
	if [ -f "${DOCKERFILE_API}" ]; then
		sed -r -i "$@" "${DOCKERFILE_API}"
	fi
}

rewrite -e "s!^(ENV HAPROXY_SRC_URL) .*!\1 ${HAPROXY_SRC_URL}!
            s!^(ENV HAPROXY_BRANCH) .*!\1 ${HAPROXY_BRANCH}!
            s!^(ENV HAPROXY_MINOR) .*!\1 ${HAPROXY_MINOR}!
            s!^(LABEL Version) .*!\1 ${HAPROXY_MINOR}!
            s!^(ENV HAPROXY_SHA256) .*!\1 ${HAPROXY_SHA256}!"

# Dataplane API and gopherd releases are looked up and pinned the same way.
# Set RELEASE_VERSIONS to every release version of haproxytech/$1, one per
# line and without the leading "v". Every page is read: a line that gets no
# new releases drops off the first page as newer ones are published. Drafts
# are skipped: they are listed for tokens that can push to the repository.
# build.sh points RELEASES_CACHE at a directory shared by all branches of a
# run, so that each list is fetched once per run
fetch_release_versions() {
	local repo="$1" page content versions cache=""
	if [ -n "${RELEASES_CACHE}" ]; then
		cache="${RELEASES_CACHE}/${repo}"
		if [ -f "${cache}" ]; then
			RELEASE_VERSIONS=$(<"${cache}")
			return 0
		fi
	fi
	RELEASE_VERSIONS=""
	for page in 1 2 3 4 5 6 7 8 9 10; do
		content=$("${CURL[@]}" "${GITHUB_AUTH[@]}" "https://api.github.com/repos/haproxytech/${repo}/releases?per_page=100&page=${page}")
		versions=$(jq -r '.[] | select(.draft | not) | .tag_name | sub("^v"; "")' <<<"${content}")
		if [ -z "${versions}" ]; then
			if [ -n "${cache}" ]; then
				printf '%s' "${RELEASE_VERSIONS}" >"${cache}.tmp"
				mv "${cache}.tmp" "${cache}"
			fi
			return 0
		fi
		RELEASE_VERSIONS+="${versions}"$'\n'
	done
	echo "More than 10 pages of ${repo} releases, refusing to update"
	exit 1
}

# Highest version in RELEASE_VERSIONS that matches the ERE $1
highest_version() {
	grep -E "$1" <<<"${RELEASE_VERSIONS}" | sort -V | tail -1
}

# Set PIN_VERSION to the version of haproxytech/$1 to pin, normally $2, and
# CHECKSUMS_SHA256 to the hash of its checksums.txt: the Dockerfile verifies
# checksums.txt against it and the downloaded tarball against checksums.txt.
# $3 and $4 are the version and hash pinned now. A release's files are not
# supposed to change once published, so a different hash for the pinned
# version means they were replaced
pin_checksums() {
	local repo="$1" version="$2" version_old="$3" sha256_old="$4"
	local file="${TMP_DIR}/${repo}-checksums.txt" release published
	PIN_VERSION="${version}"
	if ! "${CURL[@]}" -o "${file}" "https://github.com/haproxytech/${repo}/releases/download/v${version}/checksums.txt"; then
		# A new release can show up before its files are uploaded: keep the
		# pinned version for its first hours instead of failing
		release=$("${CURL[@]}" "${GITHUB_AUTH[@]}" "https://api.github.com/repos/haproxytech/${repo}/releases/tags/v${version}")
		published=$(jq -r '.published_at // empty' <<<"${release}")
		require_format "${repo} v${version} publication time" "${published}" '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$'
		if [ "${version}" = "${version_old}" ] || [ -z "${sha256_old}" ] ||
			[ $(($(date +%s) - $(date -d "${published}" +%s))) -ge $((6 * 3600)) ]; then
			echo "Cannot download checksums.txt of ${repo} v${version}"
			exit 1
		fi
		echo "checksums.txt of ${repo} v${version} not uploaded yet, keeping v${version_old}"
		PIN_VERSION="${version_old}"
		CHECKSUMS_SHA256="${sha256_old}"
		return 0
	fi
	CHECKSUMS_SHA256=$(sha256sum "${file}" | awk '{print $1}')
	require_format "${repo} checksums.txt SHA256" "${CHECKSUMS_SHA256}" '^[0-9a-f]{64}$'
	if [ "${version}" = "${version_old}" ] &&
		[ -n "${sha256_old}" ] &&
		[ "${CHECKSUMS_SHA256}" != "${sha256_old}" ]; then
		echo "checksums.txt of ${repo} v${version} changed since it was pinned, refusing to update"
		exit 1
	fi
}

update_dataplane() {
	local old checksums_old
	old=$(awk '/^ENV DATAPLANE_MINOR/ {print $NF; exit}' "${DOCKERFILE}")
	checksums_old=$(awk '/^ENV DATAPLANE_CHECKSUMS_SHA256/ {print $NF; exit}' "${DOCKERFILE}")
	require_format "pinned Dataplane API version" "${old}" '^[0-9]+\.[0-9]+\.[0-9]+$'
	fetch_release_versions dataplaneapi

	# HAProxy 2.x images ship the latest Dataplane API 3.x (plus v2 as dataplaneapi-v2),
	# so skip matching old v2.x Dataplane releases against the HAProxy branch
	DATAPLANE_MINOR=""
	case "${HAPROXY_BRANCH}" in
	2.*) ;;
	*)
		DATAPLANE_MINOR=$(highest_version "^${HAPROXY_BRANCH_RE}\.[0-9]+\$")
		;;
	esac

	# Fall back to the highest stable version of the pinned major version, as for
	# gopherd: a new major can change the dataplaneapi.yml format.
	# Only for branches without a Dataplane API line of their own (2.x, or a new
	# branch before its first Dataplane API release): a branch already on its own
	# line must not silently switch to another one
	if [ -z "${DATAPLANE_MINOR}" ]; then
		case "${old}" in
		"${HAPROXY_BRANCH}".*)
			echo "No Dataplane API ${HAPROXY_BRANCH}.x release found, refusing to switch from ${old}"
			exit 1
			;;
		esac
		DATAPLANE_MINOR=$(highest_version "^${old%%.*}\.[0-9]+\.[0-9]+\$")
	fi

	DATAPLANE_V2_MINOR=$(highest_version '^2\.[0-9]+\.[0-9]+$')

	if [ -z "${DATAPLANE_MINOR}" ]; then
		echo "Could not identify latest Dataplane API release for ${HAPROXY_BRANCH} branch"
		exit 1
	fi

	if [ -z "${DATAPLANE_V2_MINOR}" ] && grep -q "^ENV DATAPLANE_V2_MINOR" "${DOCKERFILE}"; then
		echo "Could not identify latest Dataplane API v2 release"
		exit 1
	fi

	require_format "Dataplane API version" "${DATAPLANE_MINOR}" '^[0-9]+\.[0-9]+\.[0-9]+$'
	if [ -n "${DATAPLANE_V2_MINOR}" ]; then
		require_format "Dataplane API v2 version" "${DATAPLANE_V2_MINOR}" '^2\.[0-9]+\.[0-9]+$'
	fi

	# Only for Dockerfiles that download a prebuilt Dataplane API; 2.x images
	# build it from source
	DATAPLANE_CHECKSUMS_SHA256=""
	if grep -q "^ENV DATAPLANE_CHECKSUMS_SHA256" "${DOCKERFILE}"; then
		pin_checksums dataplaneapi "${DATAPLANE_MINOR}" "${old}" "${checksums_old}"
		DATAPLANE_MINOR="${PIN_VERSION}"
		DATAPLANE_CHECKSUMS_SHA256="${CHECKSUMS_SHA256}"
	fi

	rewrite -e "s!^(ENV DATAPLANE_MINOR) .*!\1 ${DATAPLANE_MINOR}!
	            s!^(ENV DATAPLANE_V2_MINOR) .*!\1 ${DATAPLANE_V2_MINOR}!
	            s!^(ENV DATAPLANE_CHECKSUMS_SHA256) .*!\1 ${DATAPLANE_CHECKSUMS_SHA256}!"
}

# gopherd only ships in the s6 images (Dockerfile.api). Stay on the pinned
# major version: a new major can change the gopherd.yml format
update_gopherd() {
	local old checksums_old
	if ! [ -f "${DOCKERFILE_API}" ] || ! grep -q "^ARG GOPHERD_VERSION=" "${DOCKERFILE_API}"; then
		return 0
	fi
	old=$(awk -F= '/^ARG GOPHERD_VERSION=/ {print $2; exit}' "${DOCKERFILE_API}")
	checksums_old=$(awk -F= '/^ARG GOPHERD_CHECKSUMS_SHA256=/ {print $2; exit}' "${DOCKERFILE_API}")
	require_format "pinned gopherd version" "${old}" '^[0-9]+\.[0-9]+\.[0-9]+$'

	fetch_release_versions gopherd
	GOPHERD_VERSION=$(highest_version "^${old%%.*}\.[0-9]+\.[0-9]+\$")

	if [ -z "${GOPHERD_VERSION}" ]; then
		echo "Could not identify latest gopherd ${old%%.*}.x release"
		exit 1
	fi
	require_format "gopherd version" "${GOPHERD_VERSION}" '^[0-9]+\.[0-9]+\.[0-9]+$'

	pin_checksums gopherd "${GOPHERD_VERSION}" "${old}" "${checksums_old}"

	rewrite -e "s!^(ARG GOPHERD_VERSION)=.*!\1=${PIN_VERSION}!
	            s!^(ARG GOPHERD_CHECKSUMS_SHA256)=.*!\1=${CHECKSUMS_SHA256}!"
}

# Run update step $2 for $1 in a subshell, where set -e still applies and
# stops only that step: its pin stays as it was, and the HAProxy update above
# still goes out
FAILED_PARTS=""
run_part() {
	local name="$1" step="$2" status
	set +e
	(
		set -e
		"${step}"
	)
	status=$?
	set -e
	if [ "${status}" -ne 0 ]; then
		echo "Could not update ${name}, keeping its current pin"
		FAILED_PARTS="${FAILED_PARTS} ${name}"
	fi
}

run_part "Dataplane API" update_dataplane
run_part "gopherd" update_gopherd

if [ -n "${FAILED_PARTS}" ]; then
	PARTIAL="yes"
	exit "${UPDATE_PARTIAL}"
fi
