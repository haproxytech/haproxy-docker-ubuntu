#!/bin/sh
set -e

DOCKER_TAG="haproxytech/haproxy-ubuntu"
HAPROXY_BRANCHES="1.6 1.7 1.8"
HAPROXY_CURRENT_BRANCH="1.7"

for i in $HAPROXY_BRANCHES; do
    echo "Building HAProxy $i"

    DOCKERFILE="Dockerfile-$i"
    HAPROXY_MINOR_OLD=$(awk '/^ENV HAPROXY_MINOR/ {print $NF}' "$DOCKERFILE")

    ./update.sh "$i"

    HAPROXY_MINOR=$(awk '/^ENV HAPROXY_MINOR/ {print $NF}' "$DOCKERFILE")

    if [ "x$1" != "xforce" ]; then
        if [ "x$HAPROXY_MINOR_OLD" = "x$HAPROXY_MINOR" ]; then
            echo "No new releases, not building $i branch"
            continue
        fi
    fi

    docker pull $(awk '/^FROM/ {print $2}' "$DOCKERFILE")
    docker build -t "$DOCKER_TAG:$HAPROXY_MINOR" -f "$DOCKERFILE" .
    docker tag "$DOCKER_TAG:$HAPROXY_MINOR" "$DOCKER_TAG:$i"
    if [ "x$i" = "x$HAPROXY_CURRENT_BRANCH" ]; then
        docker tag "$DOCKER_TAG:$HAPROXY_MINOR" "$DOCKER_TAG:latest"
    fi
done

docker push "$DOCKER_TAG"
