#!/bin/bash

DOCKER_TAG="haproxytech/haproxy-ubuntu"
HAPROXY_GITHUB_URL="https://github.com/haproxytech/haproxy-docker-ubuntu/blob/master"
HAPROXY_BRANCHES="1.5 1.6 1.7 1.8 1.9 2.0 2.1 2.2"
HAPROXY_CURRENT_BRANCH="2.2"
PUSH="no"
HAPROXY_UPDATED=""

for i in $HAPROXY_BRANCHES; do
    echo "Building HAProxy $i"

    DOCKERFILE="$i/Dockerfile"
    HAPROXY_MINOR_OLD=$(awk '/^ENV HAPROXY_MINOR/ {print $NF}' "$DOCKERFILE")

    ./update.sh "$i" || continue

    HAPROXY_MINOR=$(awk '/^ENV HAPROXY_MINOR/ {print $NF}' "$DOCKERFILE")

    if [ "x$1" != "xforce" ]; then
        if [ "$HAPROXY_MINOR_OLD" = "$HAPROXY_MINOR" ]; then
            echo "No new releases, not building $i branch"
            continue
        fi
    fi

    PUSH="yes"
    HAPROXY_UPDATED="$HAPROXY_UPDATED $HAPROXY_MINOR"

    if [ \( "x$1" = "xtest" \) -o \( "x$2" = "xtest" \) ]; then
        docker pull $(awk '/^FROM/ {print $2}' "$DOCKERFILE")

        docker build -t "$DOCKER_TAG:$HAPROXY_MINOR" "$i" || \
            (echo "Failure building $DOCKER_TAG:$HAPROXY_MINOR"; exit 1)
        docker tag "$DOCKER_TAG:$HAPROXY_MINOR" "$DOCKER_TAG:$i"

        if [ "$i" = "$HAPROXY_CURRENT_BRANCH" ]; then
            docker tag "$DOCKER_TAG:$HAPROXY_MINOR" "$DOCKER_TAG:latest"
        fi

        docker run -it --rm "$DOCKER_TAG:$HAPROXY_MINOR" /usr/local/sbin/haproxy -c -f /usr/local/etc/haproxy/haproxy.cfg || \
            (echo "Failure testing $DOCKER_TAG:$HAPROXY_MINOR"; exit 1)
    fi

    if git tag --list | egrep -q "^$HAPROXY_MINOR$" >/dev/null 2>&1; then
        git tag -d "$HAPROXY_MINOR" || true
        git push origin ":$HAPROXY_MINOR" || true
    fi
    git commit -a -m "Automated commit triggered by $HAPROXY_MINOR release(s)" || true
    git tag "$HAPROXY_MINOR"
    git push origin "$HAPROXY_MINOR"
done

if [ "$PUSH" = "no" ]; then
        exit 0
fi

echo -e "# Supported tags and respective \`Dockerfile\` links\n" > README.md
for i in $(awk '/^ENV HAPROXY_MINOR/ {print $NF}' */Dockerfile| sort -n -r); do
        short=$(echo $i | cut -d. -f1-2 |cut -d- -f1)
        if [ "$short" = "$HAPROXY_CURRENT_BRANCH" ]; then
                if [ "$short" = "$i" ]; then
                        final="-\t[\`$i\`, \`latest\`]($HAPROXY_GITHUB_URL/$short/Dockerfile)"
                else
                        final="-\t[\`$i\`, \`$short\`, \`latest\`]($HAPROXY_GITHUB_URL/$short/Dockerfile)"
                fi
        else
                if [ "$short" = "$i" ]; then
                        final="-\t[\`$i\`]($HAPROXY_GITHUB_URL/$short/Dockerfile)"
                else
                        final="-\t[\`$i\`, \`$short\`]($HAPROXY_GITHUB_URL/$short/Dockerfile)"
                fi
        fi
        echo -e "$final" >> README.md
done
echo >> README.md
cat README_short.md >> README.md

git commit -a -m "README regen triggered by $HAPROXY_UPDATED release(s)" || true
git push
