#! /usr/bin/env sh

NIXOS_PATH=$1          

if [ -z "$NIXOS_PATH" ]; then
  echo "You must specify a path!"
  exit 1
fi


NIXOS_HOST=$2

if [ -z "$NIXOS_HOST" ]; then
  echo "You must specify a host!"
  exit 1
fi

set -e

cd $NIXOS_PATH

git add .

sudo nixos-rebuild test --flake $NIXOS_PATH#$NIXOS_HOST
