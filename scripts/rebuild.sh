#! /usr/bin/env sh

NIXOS_PATH=$1          

if [ -z "$NIXOS_PATH" ]; then
  echo "You must specify a path!"
  exit 1
fi

MESSAGE=$2

if [ -z "$MESSAGE" ]; then
  echo "You must specify a message!"
  exit 1
fi


LABEL=$3

if [ -z "$LABEL" ]; then
  echo "You must specify a label!"
  exit 1
fi

set -e

# create bootloader compatible label
SANITIZED_LABEL=$(echo "$LABEL" | sed 's/ /_/g' | sed 's/[^a-zA-Z0-9:_\.-]//g')

cd $NIXOS_PATH
git add .

# check if rebuild will work
sudo nixos-rebuild dry-activate --impure --flake $NIXOS_PATH#default

# sync git repo
cd $NIXOS_PATH
git commit -a --allow-empty -m "$MESSAGE"

if git push --dry-run; then
  git push
else
  echo "Can't push to remote. Skipping git push."
fi

# rebuild system
sudo NIXOS_LABEL="$SANITIZED_LABEL" nixos-rebuild switch --impure --flake $NIXOS_PATH#default
