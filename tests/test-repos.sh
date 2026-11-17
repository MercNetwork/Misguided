#!/usr/bin/env bash
#
# Offline test for scripts/repos.sh. Safe to run on ANY Linux machine:
# it never touches /etc/pacman.conf and never runs the real pacman.
#
#   bash tests/test-repos.sh            # pretend the CPU is x86-64-v3
#   LEVEL=znver4 bash tests/test-repos.sh
#   FAIL_ON=cachyos/pacman bash tests/test-repos.sh   # simulate a download failure
#
# How it works: we point PACMAN_CONF/PACMAN_D at a temp folder, then define
# shell functions called pacman and pacman-key. Functions win over programs
# with the same name, so repos.sh calls our fakes instead of the real tools.

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT            # clean up however the script ends

mkdir -p "$TMP/pacman.d"
cat > "$TMP/pacman.conf" <<'CONF'
[options]
HoldPkg     = pacman glibc
Architecture = auto
SigLevel    = Required DatabaseOptional

#[core-testing]
#Include = /etc/pacman.d/mirrorlist

[core]
Include = /etc/pacman.d/mirrorlist

[extra]
Include = /etc/pacman.d/mirrorlist

#[multilib]
#Include = /etc/pacman.d/mirrorlist
CONF

export PACMAN_CONF="$TMP/pacman.conf" PACMAN_D="$TMP/pacman.d"
source "$REPO_ROOT/scripts/repos.sh"

pacman() {
    echo "    (fake) pacman $*" >&2
    if [[ -n "${FAIL_ON:-}" && "$*" == *"$FAIL_ON"* ]]; then return 1; fi
    if [[ "$1" == -S* && "$*" == *kiro-mirrorlist* ]]; then touch "$PACMAN_D/kiro-mirrorlist"; fi
    return 0
}
pacman-key() { echo "    (fake) pacman-key $*" >&2; }

echo "This machine's real CPU level: $(CACHYOS_LEVEL='' detect_cachyos_level)"
echo
CACHYOS_LEVEL="${LEVEL:-v3}" setup_cachyos_repos;  echo "setup_cachyos_repos returned $?"
setup_nemesis_repo;                                echo "setup_nemesis_repo returned $?"
echo
echo "=================== resulting pacman.conf ==================="
cat "$PACMAN_CONF"
