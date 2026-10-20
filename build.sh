#!/bin/bash

DOCKER_TAG="haproxytech/haproxy-ubuntu"
HAPROXY_GITHUB_URL="https://github.com/haproxytech/haproxy-docker-ubuntu/blob/main"
# Every branch directory is built; STABLE_BRANCH names the one tagged as latest
HAPROXY_BRANCHES=$(printf '%s\n' [0-9]*/ | tr -d / | sort -V)
HAPROXY_CURRENT_BRANCH=$(cat STABLE_BRANCH 2>/dev/null)
HAPROXY_UPDATED=""
HAPROXY_FAILED=""
HAPROXY_PARTIAL=""
PUSH_FAILED=""
# Exit status of update.sh when only HAProxy could be updated
UPDATE_PARTIAL=100

# Arguments, in any order: "force" rebuilds branches without new releases,
# "test" builds and checks the images locally before committing
FORCE=""
TEST=""
for arg in "$@"; do
	case "$arg" in
	force) FORCE="yes" ;;
	test) TEST="yes" ;;
	*)
		echo "Unknown argument '$arg', expected force and/or test"
		exit 1
		;;
	esac
done

if [ -z "$HAPROXY_CURRENT_BRANCH" ]; then
	echo "Cannot read stable branch from STABLE_BRANCH"
	exit 1
fi

# Branch directories get reset with git checkout below, which would silently
# discard local edits
if ! git diff --quiet HEAD --; then
	echo "Uncommitted changes in the working tree, refusing to run"
	exit 1
fi

GIT_BRANCH=$(git symbolic-ref --short HEAD) || exit 1

# update.sh fetches each GitHub release list once per run into this
# directory instead of once per branch, which keeps a run well within the
# API rate limit even without a GH_TOKEN
RELEASES_CACHE=$(mktemp -d) || exit 1
trap 'rm -rf "$RELEASES_CACHE"' EXIT
export RELEASES_CACHE

test_image() {
	local dockerfile="$1" tag="$2" context="$3"

	docker build --pull -f "$dockerfile" -t "$tag" "$context" ||
		{
			echo "Failure building $tag"
			return 1
		}

	docker run --rm --entrypoint /usr/local/sbin/haproxy "$tag" -c -f /usr/local/etc/haproxy/haproxy.cfg ||
		{
			echo "Failure testing $tag"
			return 1
		}
}

# Build and check the plain image and, when there is one, the s6 image of
# branch $1 at release $2
test_branch() {
	local branch="$1" minor="$2"

	test_image "$branch/Dockerfile" "$DOCKER_TAG:$minor" "$branch" || return 1
	docker tag "$DOCKER_TAG:$minor" "$DOCKER_TAG:$branch"
	if [ "$branch" = "$HAPROXY_CURRENT_BRANCH" ]; then
		docker tag "$DOCKER_TAG:$minor" "$DOCKER_TAG:latest"
	fi

	if [ -f "$branch/Dockerfile.api" ]; then
		test_image "$branch/Dockerfile.api" "$DOCKER_TAG:s6-$minor" "$branch" || return 1
	fi
}

# Succeeds when version $2 is older than version $1
is_downgrade() {
	[ "$(printf '%s\n' "$1" "$2" | sort -V | tail -1)" != "$2" ]
}

push_release() {
	local tag="$1" remote_ref remote_head

	# Check first that the push can succeed: deleting the old tag and then
	# failing would leave the release without a tag, and image tagging relies
	# on the tags to tell which release of a branch is the newest. Read the ref
	# on its own: in a pipeline a failed ls-remote would go unnoticed and skip
	# the check
	remote_ref=$(git ls-remote origin "refs/heads/$GIT_BRANCH") ||
		{
			echo "Cannot read origin/$GIT_BRANCH"
			return 1
		}
	remote_head=$(echo "$remote_ref" | cut -f1)
	if [ -n "$remote_head" ] && ! git merge-base --is-ancestor "$remote_head" HEAD 2>/dev/null; then
		echo "origin/$GIT_BRANCH has new commits, not pushing $tag"
		return 1
	fi

	git tag -f "$tag"
	# Recreate rather than move an existing tag, so the push always triggers a build
	git push origin ":refs/tags/$tag" 2>/dev/null || true
	# Push the commit and its tag together, one tag per push: GitHub does not
	# trigger workflows when more than three tags are pushed at once
	git push --atomic origin HEAD "refs/tags/$tag" ||
		{
			echo "Failure pushing $tag"
			return 1
		}
}

for i in $HAPROXY_BRANCHES; do
	echo "Building HAProxy $i"

	DOCKERFILE="$i/Dockerfile"
	DOCKERFILE_API="$i/Dockerfile.api"
	HAPROXY_MINOR_OLD=$(awk '/^ENV HAPROXY_MINOR/ {print $NF; exit}' "$DOCKERFILE")
	HAPROXY_SHA256_OLD=$(awk '/^ENV HAPROXY_SHA256/ {print $NF; exit}' "$DOCKERFILE")
	DATAPLANE_MINOR_OLD=$(awk '/^ENV DATAPLANE_MINOR/ {print $NF; exit}' "$DOCKERFILE")
	DATAPLANE_V2_MINOR_OLD=$(awk '/^ENV DATAPLANE_V2_MINOR/ {print $NF; exit}' "$DOCKERFILE")
	GOPHERD_VERSION_OLD=""
	if [ -f "$DOCKERFILE_API" ]; then
		GOPHERD_VERSION_OLD=$(awk -F= '/^ARG GOPHERD_VERSION=/ {print $2; exit}' "$DOCKERFILE_API")
	fi

	# Status UPDATE_PARTIAL: HAProxy was updated but Dataplane API or gopherd
	# kept its pin. The HAProxy update still ships; the run fails at the end
	./update.sh "$i"
	UPDATE_STATUS=$?
	if [ "$UPDATE_STATUS" -eq "$UPDATE_PARTIAL" ]; then
		HAPROXY_PARTIAL="$HAPROXY_PARTIAL $i"
	elif [ "$UPDATE_STATUS" -ne 0 ]; then
		echo "Failure updating $i branch"
		HAPROXY_FAILED="$HAPROXY_FAILED $i"
		git checkout -- "$i"
		continue
	fi

	HAPROXY_MINOR=$(awk '/^ENV HAPROXY_MINOR/ {print $NF; exit}' "$DOCKERFILE")
	HAPROXY_SHA256=$(awk '/^ENV HAPROXY_SHA256/ {print $NF; exit}' "$DOCKERFILE")
	DATAPLANE_MINOR=$(awk '/^ENV DATAPLANE_MINOR/ {print $NF; exit}' "$DOCKERFILE")
	DATAPLANE_V2_MINOR=$(awk '/^ENV DATAPLANE_V2_MINOR/ {print $NF; exit}' "$DOCKERFILE")
	GOPHERD_VERSION=""
	if [ -f "$DOCKERFILE_API" ]; then
		GOPHERD_VERSION=$(awk -F= '/^ARG GOPHERD_VERSION=/ {print $2; exit}' "$DOCKERFILE_API")
	fi

	# Never go backwards, e.g. to a stale devel release after a failed lookup
	DOWNGRADE=""
	is_downgrade "$HAPROXY_MINOR_OLD" "$HAPROXY_MINOR" &&
		DOWNGRADE="HAProxy from $HAPROXY_MINOR_OLD to $HAPROXY_MINOR"
	is_downgrade "$DATAPLANE_MINOR_OLD" "$DATAPLANE_MINOR" &&
		DOWNGRADE="Dataplane API from $DATAPLANE_MINOR_OLD to $DATAPLANE_MINOR"
	is_downgrade "$DATAPLANE_V2_MINOR_OLD" "$DATAPLANE_V2_MINOR" &&
		DOWNGRADE="Dataplane API v2 from $DATAPLANE_V2_MINOR_OLD to $DATAPLANE_V2_MINOR"
	is_downgrade "$GOPHERD_VERSION_OLD" "$GOPHERD_VERSION" &&
		DOWNGRADE="gopherd from $GOPHERD_VERSION_OLD to $GOPHERD_VERSION"
	if [ -n "$DOWNGRADE" ]; then
		echo "Refusing to downgrade $DOWNGRADE in $i branch"
		HAPROXY_FAILED="$HAPROXY_FAILED $i"
		git checkout -- "$i"
		continue
	fi

	if [ -z "$FORCE" ]; then
		if [ "$HAPROXY_MINOR_OLD" = "$HAPROXY_MINOR" ] &&
			[ "$HAPROXY_SHA256_OLD" = "$HAPROXY_SHA256" ] &&
			[ "$DATAPLANE_MINOR_OLD" = "$DATAPLANE_MINOR" ] &&
			[ "$DATAPLANE_V2_MINOR_OLD" = "$DATAPLANE_V2_MINOR" ] &&
			[ "$GOPHERD_VERSION_OLD" = "$GOPHERD_VERSION" ]; then
			echo "No new releases, not building $i branch"
			git checkout -- "$i"
			continue
		fi
	fi

	# A branch whose images do not build is skipped like a failed update, so
	# the remaining branches still get their releases
	if [ -n "$TEST" ] && ! test_branch "$i" "$HAPROXY_MINOR"; then
		HAPROXY_FAILED="$HAPROXY_FAILED $i"
		git checkout -- "$i"
		continue
	fi

	# Name what changed in the commit message; only HAProxy releases are
	# listed in the README commit message
	if [ "$HAPROXY_MINOR_OLD" != "$HAPROXY_MINOR" ]; then
		COMMIT_MSG="Automated commit triggered by $HAPROXY_MINOR release(s)"
	elif [ "$HAPROXY_SHA256_OLD" != "$HAPROXY_SHA256" ]; then
		COMMIT_MSG="Automated commit triggered by a replaced HAProxy $HAPROXY_MINOR tarball"
	elif [ "$DATAPLANE_MINOR_OLD" != "$DATAPLANE_MINOR" ]; then
		COMMIT_MSG="Automated commit triggered by Dataplane API $DATAPLANE_MINOR release for $HAPROXY_MINOR"
	elif [ "$DATAPLANE_V2_MINOR_OLD" != "$DATAPLANE_V2_MINOR" ]; then
		COMMIT_MSG="Automated commit triggered by Dataplane API $DATAPLANE_V2_MINOR release for $HAPROXY_MINOR"
	elif [ "$GOPHERD_VERSION_OLD" != "$GOPHERD_VERSION" ]; then
		COMMIT_MSG="Automated commit triggered by gopherd $GOPHERD_VERSION release for $HAPROXY_MINOR"
	else
		COMMIT_MSG="Automated rebuild of $HAPROXY_MINOR"
	fi

	# Only commit when something changed (force rebuilds have nothing to
	# commit), and never tag after a failed commit: the tag would point at
	# the previous release's files under the new version
	if ! git diff --quiet HEAD -- "$i"; then
		if ! git commit -m "$COMMIT_MSG" -- "$i"; then
			echo "Failure committing $i branch"
			HAPROXY_FAILED="$HAPROXY_FAILED $i"
			git checkout HEAD -- "$i"
			continue
		fi
	fi
	if [ "$HAPROXY_MINOR_OLD" != "$HAPROXY_MINOR" ]; then
		HAPROXY_UPDATED="$HAPROXY_UPDATED $HAPROXY_MINOR"
	fi
	# The remaining branches and the README would fail to push the same way:
	# stop there, but still report everything below
	if ! push_release "$HAPROXY_MINOR"; then
		HAPROXY_FAILED="$HAPROXY_FAILED $i"
		PUSH_FAILED="$i"
		break
	fi
done

HAPROXY_NOT_PROCESSED=""
if [ -n "$PUSH_FAILED" ]; then
	after=""
	for j in $HAPROXY_BRANCHES; do
		if [ -n "$after" ]; then
			HAPROXY_NOT_PROCESSED="$HAPROXY_NOT_PROCESSED $j"
		fi
		if [ "$j" = "$PUSH_FAILED" ]; then
			after="yes"
		fi
	done
fi

# Regenerate on every run, so STABLE_BRANCH or branch directory changes show
# up without waiting for a release; it is only committed when it changed.
# Not after a failed push: pushing the README would fail the same way
README_FAILED=""
if [ -n "$PUSH_FAILED" ]; then
	README_FAILED="README.md not regenerated after the failed push"
else
	echo -e "# Supported tags and respective \`Dockerfile\` links\n" >README.md
	while read -r i; do
		short=$(echo "$i" | cut -d. -f1-2 | cut -d- -f1)
		# s6 images are only built for branches with a Dockerfile.api
		s6=""
		if [ -f "$short/Dockerfile.api" ]; then
			s6="yes"
		fi
		tags="\`$i\`"
		[ -n "$s6" ] && tags="$tags, \`s6-$i\`"
		if [ "$short" != "$i" ]; then
			tags="$tags, \`$short\`"
			[ -n "$s6" ] && tags="$tags, \`s6-$short\`"
		fi
		if [ "$short" = "$HAPROXY_CURRENT_BRANCH" ]; then
			tags="$tags, \`latest\`"
			[ -n "$s6" ] && tags="$tags, \`s6-latest\`"
		fi
		echo -e "-\t[$tags]($HAPROXY_GITHUB_URL/$short/Dockerfile)" >>README.md
	done < <(awk '/^ENV HAPROXY_MINOR/ {print $NF}' ./*/Dockerfile | sort -u -r -V)
	echo >>README.md
	cat README_short.md >>README.md

	if ! git diff --quiet -- README.md; then
		README_MSG="README regen"
		if [ -n "$HAPROXY_UPDATED" ]; then
			README_MSG="README regen triggered by${HAPROXY_UPDATED} release(s)"
		fi
		if ! git commit -m "$README_MSG" -- README.md; then
			README_FAILED="Failure committing README.md"
		elif ! git push origin HEAD; then
			README_FAILED="Failure pushing README.md"
		fi
	fi
fi

# Fail the run so that skipped branches and held back Dataplane API or
# gopherd updates do not go unnoticed
if [ -n "$HAPROXY_PARTIAL" ]; then
	echo "Branches that kept their Dataplane API or gopherd pin:$HAPROXY_PARTIAL"
fi
if [ -n "$HAPROXY_FAILED" ]; then
	echo "Failed branches:$HAPROXY_FAILED"
fi
if [ -n "$HAPROXY_NOT_PROCESSED" ]; then
	echo "Branches not processed after the failed push:$HAPROXY_NOT_PROCESSED"
fi
if [ -n "$README_FAILED" ]; then
	echo "$README_FAILED"
fi
if [ -n "$HAPROXY_PARTIAL" ] || [ -n "$HAPROXY_FAILED" ] || [ -n "$README_FAILED" ]; then
	exit 1
fi
