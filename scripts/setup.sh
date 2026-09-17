#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT"
if pkg-config --exists libcurl; then
  exit 0
fi
# Install development headers locally without root or package lifecycle scripts.
mkdir -p vendor
cd vendor
apt-get download libcurl4-openssl-dev
for package in libcurl4-openssl-dev_*.deb; do
  dpkg-deb -x "$package" curl-dev
done
