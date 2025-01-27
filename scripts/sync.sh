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


cd $NIXOS_PATH

# add files to repo
git add .

# Save current HEAD hash
before_hash=$(git rev-parse HEAD)

# sync with repo
git pull --rebase

# Save new HEAD hash
after_hash=$(git rev-parse HEAD)


# Compare the hashes
if [ "$before_hash" != "$after_hash" ]; then
  echo "Changes were pulled and applied."

  sudo NIXOS_LABEL="sync $NIXOS_HOST" nixos-rebuild switch --impure --flake $NIXOS_PATH#$NIXOS_HOST
else
  echo "No changes were pulled."
fi
