#!/bin/sh
#
# Build the ecocor-api EXPath package (XAR).
#
# Usage:
#   ./build.sh          build build/ecocor-<version>.xar
#   ./build.sh clean    remove build artifacts
#
# The version is derived from `git describe` unless set with the VERSION
# environment variable.

set -e

cd "$(dirname "$0")"

name=ecocor
build_dir=build
symlink=$name-latest.xar

if [ "$1" = clean ]; then
  rm -rf $build_dir expath-pkg.xml $symlink
  exit
fi

if [ -z "$VERSION" ]; then
  VERSION=$(git describe --tags --always --dirty 2>/dev/null | sed -e 's/^v//')
fi
version=${VERSION:-unknown}
case $version in
  *[!A-Za-z0-9._-]*)
    echo "Unexpected characters in version: $version" >&2
    exit 1
    ;;
esac
xar=$build_dir/$name-$version.xar

sed -e "s/@package.version@/$version/" expath-pkg.xml.tmpl > expath-pkg.xml

mkdir -p $build_dir
rm -f "$xar"
zip -q -r "$xar" \
  repo.xml \
  expath-pkg.xml \
  pre-install.xq \
  post-install.xq \
  collection.xconf \
  data.xconf \
  api.yaml \
  modules \
  jobs \
  README.md \
  -x '*/.DS_Store' '*~' '*/.#*'

ln -sf "$xar" $symlink

echo "$xar"
