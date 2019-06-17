#!/bin/sh
set -e

DOCKER_TAG="haproxytech/haproxy-ubuntu"
HAPROXY_BRANCHES="1.6 1.7 1.8 1.9 2.0 2.1"
HAPROXY_CURRENT_BRANCH="2.0"
PUSH="no"

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
        else
            PUSH="yes"
        fi
    else
        PUSH="yes"
    fi

    docker pull $(awk '/^FROM/ {print $2}' "$DOCKERFILE")
    docker build -t "$DOCKER_TAG:$HAPROXY_MINOR" -f "$DOCKERFILE" .
    docker tag "$DOCKER_TAG:$HAPROXY_MINOR" "$DOCKER_TAG:$i"
    if [ "x$i" = "x$HAPROXY_CURRENT_BRANCH" ]; then
        docker tag "$DOCKER_TAG:$HAPROXY_MINOR" "$DOCKER_TAG:latest"
    fi
done

if [ "x$PUSH" = "xyes" ]; then
    docker push "$DOCKER_TAG"
fi
