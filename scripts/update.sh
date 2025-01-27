#! /usr/bin/env sh

NIXOS_PATH=$1          

if [ -z "$NIXOS_PATH" ]; then
  echo "You must specify a path!"
  exit 1
fi

INPUT_NAME=$2

cd $NIXOS_PATH
nix flake update $INPUT_NAME
