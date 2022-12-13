#!/usr/bin/env bash
set -Eeuo pipefail
set -x
base="busyboxturbo"

docker build -t "$base-builder" -f "Dockerfile.builder" .
docker run --rm "$base-builder" tar cC rootfs . | xz -T0 -z9 > "./busybox.tar.xz"
docker build -t "$base" .
docker run --rm "$base" sh -xec 'true'

docker images "$base"
