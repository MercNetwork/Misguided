#!/bin/bash
#github-action genshdoc
#
# @file curl-install
# @brief One-line bootstrapper: installs git, clones MisguidedArch, and starts it.
#
# Usage from the Arch ISO (after you publish your fork):
#   bash <(curl -L https://raw.githubusercontent.com/YOUR_GITHUB_USERNAME/MisguidedArch/main/scripts/curl-install.sh)

# Change this to the URL of YOUR copy of the repository.
REPO_URL="https://github.com/YOUR_GITHUB_USERNAME/MisguidedArch"

# Checking if is running in Repo Folder
if [[ "$(basename "$(pwd)" | tr '[:upper:]' '[:lower:]')" =~ ^scripts$ ]]; then
    echo "You are running this in MisguidedArch Folder."
    echo "Please use ./misguidedarch.sh instead"
    exit
fi

# Installing git

echo "Installing git."
pacman -Sy --noconfirm --needed git glibc

echo "Cloning the MisguidedArch Project"
git clone "$REPO_URL" "$HOME/MisguidedArch"

echo "Executing MisguidedArch Script"

cd "$HOME/MisguidedArch" || exit 1

exec ./misguidedarch.sh
