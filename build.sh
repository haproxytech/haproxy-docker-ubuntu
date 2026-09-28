#!/bin/bash

DOCKER_TAG="haproxytech/haproxy-ubuntu"
HAPROXY_GITHUB_URL="https://github.com/haproxytech/haproxy-docker-ubuntu/blob/main"
# Every branch directory is built; STABLE_BRANCH names the one tagged as latest
HAPROXY_BRANCHES=$(ls -d [0-9]*/ | tr -d / | sort -V)
HAPROXY_CURRENT_BRANCH=$(cat STABLE_BRANCH)
PUSH="no"
HAPROXY_UPDATED=""

test_image() {
    local dockerfile="$1" tag="$2" context="$3"

    docker build --pull -f "$dockerfile" -t "$tag" "$context" || \
        { echo "Failure building $tag"; exit 1; }

    docker run --rm --entrypoint /usr/local/sbin/haproxy "$tag" -c -f /usr/local/etc/haproxy/haproxy.cfg || \
        { echo "Failure testing $tag"; exit 1; }
}

for i in $HAPROXY_BRANCHES; do
    echo "Building HAProxy $i"

    DOCKERFILE="$i/Dockerfile"
    DOCKERFILE_API="$i/Dockerfile.api"
    HAPROXY_MINOR_OLD=$(awk '/^ENV HAPROXY_MINOR/ {print $NF; exit}' "$DOCKERFILE")
    DATAPLANE_MINOR_OLD=$(awk '/^ENV DATAPLANE_MINOR/ {print $NF; exit}' "$DOCKERFILE")
    DATAPLANE_V2_MINOR_OLD=$(awk '/^ENV DATAPLANE_V2_MINOR/ {print $NF; exit}' "$DOCKERFILE")

    if ! ./update.sh "$i"; then
        git checkout -- "$i"
        continue
    fi

    HAPROXY_MINOR=$(awk '/^ENV HAPROXY_MINOR/ {print $NF; exit}' "$DOCKERFILE")
    DATAPLANE_MINOR=$(awk '/^ENV DATAPLANE_MINOR/ {print $NF; exit}' "$DOCKERFILE")
    DATAPLANE_V2_MINOR=$(awk '/^ENV DATAPLANE_V2_MINOR/ {print $NF; exit}' "$DOCKERFILE")

    # Never go backwards, e.g. to a stale devel release after a failed lookup
    if [ "$(printf '%s\n' "$HAPROXY_MINOR_OLD" "$HAPROXY_MINOR" | sort -V | tail -1)" != "$HAPROXY_MINOR" ]; then
        echo "Refusing to downgrade $i branch from $HAPROXY_MINOR_OLD to $HAPROXY_MINOR"
        git checkout -- "$i"
        continue
    fi

    if [ "x$1" != "xforce" ]; then
        if [ "$HAPROXY_MINOR_OLD" = "$HAPROXY_MINOR" ] && \
           [ "$DATAPLANE_MINOR_OLD" = "$DATAPLANE_MINOR" ] && \
           [ "$DATAPLANE_V2_MINOR_OLD" = "$DATAPLANE_V2_MINOR" ]; then
            echo "No new releases, not building $i branch"
            git checkout -- "$i"
            continue
        fi
    fi

    PUSH="yes"
    HAPROXY_UPDATED="$HAPROXY_UPDATED $HAPROXY_MINOR"

    if [ \( "x$1" = "xtest" \) -o \( "x$2" = "xtest" \) ]; then
        test_image "$DOCKERFILE" "$DOCKER_TAG:$HAPROXY_MINOR" "$i"
        docker tag "$DOCKER_TAG:$HAPROXY_MINOR" "$DOCKER_TAG:$i"

        if [ "$i" = "$HAPROXY_CURRENT_BRANCH" ]; then
            docker tag "$DOCKER_TAG:$HAPROXY_MINOR" "$DOCKER_TAG:latest"
        fi

        if [ -f "$DOCKERFILE_API" ]; then
            test_image "$DOCKERFILE_API" "$DOCKER_TAG:s6-$HAPROXY_MINOR" "$i"
        fi
    fi

    git commit -m "Automated commit triggered by $HAPROXY_MINOR release(s)" -- "$i" || true
    git tag -f "$HAPROXY_MINOR"
    # Recreate rather than move an existing tag, so the push always triggers a build
    git push origin ":refs/tags/$HAPROXY_MINOR" 2>/dev/null || true
    # Push the commit and its tag together, one tag per push: GitHub does not
    # trigger workflows when more than three tags are pushed at once
    git push --atomic origin HEAD "refs/tags/$HAPROXY_MINOR" || \
        { echo "Failure pushing $HAPROXY_MINOR"; exit 1; }
done

if [ "$PUSH" = "no" ]; then
        exit 0
fi

echo -e "# Supported tags and respective \`Dockerfile\` links\n" > README.md
for i in $(awk '/^ENV HAPROXY_MINOR/ {print $NF}' */Dockerfile | sort -u -r -V); do
        short=$(echo $i | cut -d. -f1-2 |cut -d- -f1)
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
        echo -e "-\t[$tags]($HAPROXY_GITHUB_URL/$short/Dockerfile)" >> README.md
done
echo >> README.md
cat README_short.md >> README.md

git commit -m "README regen triggered by $HAPROXY_UPDATED release(s)" -- README.md || true
git push
