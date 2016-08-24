#!/bin/sh
set -e

DOCKER_TAG="haproxytech/haproxy-ubuntu"

HAPROXY_MINOR_OLD=$(awk '/^ENV HAPROXY_MINOR/ {print $NF}' Dockerfile)

./update.sh

HAPROXY_MINOR=$(awk '/^ENV HAPROXY_MINOR/ {print $NF}' Dockerfile)

if [ "x$1" != "xforce" ]; then
    if [ "x$HAPROXY_MINOR_OLD" = "x$HAPROXY_MINOR" ]; then
        echo "No new releases, not building anything."
        exit 0
    fi
fi

sudo docker build -t "$DOCKER_TAG:$HAPROXY_MINOR" .
sudo docker tag "$DOCKER_TAG:$HAPROXY_MINOR" "$DOCKER_TAG:latest"
sudo docker push "$DOCKER_TAG"
