#!/usr/bin/env bash
#github-action genshdoc
#
# @file Repos
# @brief Functions that add the CachyOS repositories (as the primary repos) and
#        Erik Dubois' nemesis_repo (for the Arch Linux Tweak Tool) to pacman.conf.
#
# This file is a *library*: it only defines variables and functions.
# Nothing happens until another script runs:
#
#   source "$HOME/MisguidedArch/scripts/repos.sh"
#   setup_cachyos_repos
#   setup_nemesis_repo
#
# 1-setup.sh does exactly that, as root, inside arch-chroot.
#
# Every function returns 0 on success and 1 on failure. On failure it puts
# pacman.conf back the way it was, so the install carries on with plain Arch.

# ---------------------------------------------------------------------------
# Settings. Each one can be overridden by exporting it before sourcing,
# e.g.  PACMAN_CONF=/tmp/test.conf source scripts/repos.sh
# ---------------------------------------------------------------------------
PACMAN_CONF="${PACMAN_CONF:-/etc/pacman.conf}"
PACMAN_D="${PACMAN_D:-/etc/pacman.d}"
KEYSERVER="${KEYSERVER:-keyserver.ubuntu.com}"

# CachyOS signing key (from the CachyOS wiki).
CACHYOS_KEY="F3B607488DB35A47"
# Single quotes: pacman, not bash, must expand $arch and $repo.
CACHYOS_BOOTSTRAP_SERVER='https://mirror.cachyos.org/repo/$arch/$repo'

NEMESIS_SERVER='https://erikdubois.github.io/$repo/$arch'
# Kiro signing key that nemesis_repo packages are signed with
# (same ID Erik's arcolinux-nemesis uses in install_kiro_keyring_and_mirrorlist).
KIRO_KEY="149ABD0C3A0563EE"

# Comment markers let us find (and delete) the blocks we wrote.
MARK_START="# >>> MisguidedArch"
MARK_END="# <<< MisguidedArch"

# ---------------------------------------------------------------------------
# Small helpers
# ---------------------------------------------------------------------------

# @description Print a highlighted status line.
# @arg $1 string Message.
repo_msg() {
    echo -e "\e[1;36m[repos]\e[0m $1"
}

# @description Insert a block of text on the line above the first [core] section.
#   pacman reads repos top to bottom and uses the first one that has a package,
#   so "above [core]" is what makes a repo the *main* repo.
# @arg $1 string The block to insert (may contain newlines).
insert_before_core() {
    local block="$1"
    local tmp
    tmp="$(mktemp)"
    # ENVIRON[] instead of awk -v so that backslashes are passed through untouched.
    BLOCK="$block" awk '
        !done && /^\[core\]/ { print ENVIRON["BLOCK"]; print ""; done = 1 }
        { print }
    ' "$PACMAN_CONF" > "$tmp"
    # cat > keeps the original file's owner and permissions (mv would not).
    cat "$tmp" > "$PACMAN_CONF"
    rm -f "$tmp"
}

# @description Append a block of text to the end of pacman.conf.
# @arg $1 string The block to append.
append_to_conf() {
    printf '\n%s\n' "$1" >> "$PACMAN_CONF"
    squeeze_blank_lines
}

# @description Collapse every run of blank lines in pacman.conf into one blank line.
squeeze_blank_lines() {
    sed -i '/^$/N;/^\n$/D' "$PACMAN_CONF"
}

# @description Delete everything between "MARK_START <tag>" and "MARK_END <tag>".
# @arg $1 string Tag used when the block was written (e.g. cachyos-bootstrap).
remove_marked_block() {
    local tag="$1"
    sed -i "/^${MARK_START} ${tag}\$/,/^${MARK_END} ${tag}\$/d" "$PACMAN_CONF"
    squeeze_blank_lines        # tidy the gap the block leaves behind
}

# @description Wrap lines in start/end markers so remove_marked_block can find them.
# @arg $1 string Tag.
# @arg $@ string The lines that go between the markers.
marked_block() {
    local tag="$1"
    shift
    printf '%s\n' "${MARK_START} ${tag}" "$@" "${MARK_END} ${tag}"
}

# @description Load every keyring a package ships into pacman's keyring.
#   Keyring packages normally do this themselves; doing it again is harmless
#   and covers packages whose install script did not run inside the chroot.
# @arg $1 string Package name (e.g. kiro-keyring).
populate_keyring_from_pkg() {
    local pkg="$1" file name
    while read -r _ file; do
        name="$(basename "$file" .gpg)"        # /usr/share/pacman/keyrings/kiro.gpg -> kiro
        pacman-key --populate "$name" >/dev/null 2>&1 || true
    done < <(pacman -Ql "$pkg" 2>/dev/null | grep '/usr/share/pacman/keyrings/[^/]*\.gpg$' | grep -v -- '-revoked\|-trusted')
}

# ---------------------------------------------------------------------------
# CachyOS
# ---------------------------------------------------------------------------

# @description Work out which CachyOS build of the repos this CPU can run.
#   Prints one of: znver4, v4, v3, generic.
#   Set CACHYOS_LEVEL beforehand to skip detection (e.g. CACHYOS_LEVEL=v3).
# @stdout The level.
detect_cachyos_level() {
    if [[ -n "${CACHYOS_LEVEL:-}" ]]; then
        echo "$CACHYOS_LEVEL"
        return 0
    fi

    # glibc's dynamic loader reports which x86-64 levels the CPU supports.
    local ld_help
    ld_help="$(/lib/ld-linux-x86-64.so.2 --help 2>/dev/null)"

    if grep -q 'x86-64-v4 (supported, searched)' <<< "$ld_help"; then
        # AMD Zen 4 / Zen 5 get their own, even more tuned, builds.
        if gcc -march=native -Q --help=target 2>/dev/null | grep -Eq -- '-march=[[:space:]]+znver[45]'; then
            echo znver4
        else
            echo v4
        fi
    elif grep -q 'x86-64-v3 (supported, searched)' <<< "$ld_help"; then
        echo v3
    else
        echo generic
    fi
}

# @description Build the pacman.conf block for a CachyOS level.
# @arg $1 string Level from detect_cachyos_level.
# @stdout The repo sections, in priority order.
cachyos_repo_block() {
    local level="$1" mirrorlist suffix repo

    case "$level" in
        znver4) suffix="znver4"; mirrorlist="cachyos-v4-mirrorlist" ;;
        v4)     suffix="v4";     mirrorlist="cachyos-v4-mirrorlist" ;;
        v3)     suffix="v3";     mirrorlist="cachyos-v3-mirrorlist" ;;
        *)      suffix="" ;;
    esac

    if [[ -n "$suffix" ]]; then
        for repo in "cachyos-${suffix}" "cachyos-core-${suffix}" "cachyos-extra-${suffix}"; do
            printf '[%s]\nInclude = %s/%s\n' "$repo" "$PACMAN_D" "$mirrorlist"
        done
    fi
    # The plain [cachyos] repo is always last; it holds the kernels, tools and pacman fork.
    printf '[cachyos]\nInclude = %s/cachyos-mirrorlist\n' "$PACMAN_D"
}

# @description Set pacman's Architecture line so it accepts the optimised packages.
# @arg $1 string Level from detect_cachyos_level.
set_pacman_architecture() {
    local arch
    case "$1" in
        znver4|v4) arch="x86_64 x86_64_v3 x86_64_v4" ;;
        v3)        arch="x86_64 x86_64_v3" ;;
        *)         return 0 ;;                       # generic: leave "auto" alone
    esac
    sed -i "s/^Architecture[[:space:]]*=.*/Architecture = ${arch}/" "$PACMAN_CONF"
}

# @description Put a backed-up pacman.conf back and re-sync the package databases.
# @arg $1 string Path of the backup file.
restore_pacman_conf() {
    repo_msg "CachyOS setup failed - restoring ${PACMAN_CONF} and continuing with Arch repos."
    cat "$1" > "$PACMAN_CONF"
    pacman -Syy --noconfirm >/dev/null 2>&1
}

# @description Make the CachyOS repositories the main repositories.
#   1. trust the CachyOS key
#   2. temporarily add [cachyos] with a direct server URL
#   3. install keyring, mirrorlists and CachyOS' pacman from it
#   4. swap the temporary block for the real blocks above [core]
#   5. sync and upgrade so the base system comes from CachyOS
# @exitcode 0 Repos added.
# @exitcode 1 Something failed; pacman.conf was restored.
setup_cachyos_repos() {
    local level backup="${PACMAN_CONF}.pre-cachyos"

    if grep -q '^\[cachyos\]' "$PACMAN_CONF"; then
        repo_msg "CachyOS repos already present, skipping."
        return 0
    fi

    level="$(detect_cachyos_level)"
    repo_msg "CPU supports CachyOS level: ${level}"

    cp "$PACMAN_CONF" "$backup"

    repo_msg "Importing CachyOS signing key ${CACHYOS_KEY}"
    pacman-key --recv-keys "$CACHYOS_KEY" --keyserver "$KEYSERVER" || { restore_pacman_conf "$backup"; return 1; }
    pacman-key --lsign-key "$CACHYOS_KEY"                            || { restore_pacman_conf "$backup"; return 1; }

    repo_msg "Bootstrapping keyring, mirrorlists and pacman from [cachyos]"
    insert_before_core "$(marked_block cachyos-bootstrap '[cachyos]' "Server = ${CACHYOS_BOOTSTRAP_SERVER}")"
    pacman -Sy --noconfirm --needed \
        cachyos/cachyos-keyring \
        cachyos/cachyos-mirrorlist \
        cachyos/cachyos-v3-mirrorlist \
        cachyos/cachyos-v4-mirrorlist \
        cachyos/pacman || { restore_pacman_conf "$backup"; return 1; }
    populate_keyring_from_pkg cachyos-keyring
    remove_marked_block cachyos-bootstrap

    repo_msg "Writing CachyOS ${level} repos above [core]"
    insert_before_core "$(marked_block cachyos "# CachyOS level: ${level}" "$(cachyos_repo_block "$level")")"
    set_pacman_architecture "$level"

    repo_msg "Switching installed packages to CachyOS builds (pacman -Syyu)"
    pacman -Syyu --noconfirm || { restore_pacman_conf "$backup"; return 1; }

    repo_msg "CachyOS repos active. Backup of the old config: ${backup}"
    return 0
}

# ---------------------------------------------------------------------------
# nemesis_repo (Erik Dubois) - provides archlinux-tweak-tool
# ---------------------------------------------------------------------------

# @description Add Erik Dubois' nemesis_repo, which ships the Arch Linux Tweak Tool (ATT).
#   The repo is signed with the Kiro key, so we trust that key first (like CachyOS's),
#   add the repo with a direct Server line, install kiro-keyring + kiro-mirrorlist,
#   then switch to the mirrorlist. Signatures are checked at every step.
# @exitcode 0 Repo added.
# @exitcode 1 Something failed; the repo was removed again.
setup_nemesis_repo() {
    if grep -q '^\[nemesis_repo\]' "$PACMAN_CONF"; then
        repo_msg "nemesis_repo already present, skipping."
        return 0
    fi

    repo_msg "Importing Kiro signing key ${KIRO_KEY}"
    if ! pacman-key --recv-keys "$KIRO_KEY" --keyserver "$KEYSERVER"; then
        # second keyserver, as Erik's script does
        if ! pacman-key --recv-keys "$KIRO_KEY" --keyserver keys.openpgp.org; then
            repo_msg "Could not get the Kiro key - skipping nemesis_repo (ATT will not be installed)."
            return 1
        fi
    fi
    pacman-key --lsign-key "$KIRO_KEY"

    repo_msg "Bootstrapping kiro-keyring and kiro-mirrorlist from nemesis_repo"
    # No SigLevel line: the global "Required" applies, and the key above is now trusted.
    append_to_conf "$(marked_block nemesis-bootstrap '[nemesis_repo]' "Server = ${NEMESIS_SERVER}")"

    if ! pacman -Sy --noconfirm --needed nemesis_repo/kiro-keyring nemesis_repo/kiro-mirrorlist; then
        repo_msg "Could not reach nemesis_repo - skipping it (ATT will not be installed)."
        remove_marked_block nemesis-bootstrap
        return 1
    fi
    populate_keyring_from_pkg kiro-keyring
    remove_marked_block nemesis-bootstrap

    # Same repo, now using the mirrorlist that kiro-mirrorlist installed.
    if [[ -f "${PACMAN_D}/kiro-mirrorlist" ]]; then
        append_to_conf "$(marked_block nemesis '[nemesis_repo]' "Include = ${PACMAN_D}/kiro-mirrorlist")"
    else
        append_to_conf "$(marked_block nemesis '[nemesis_repo]' "Server = ${NEMESIS_SERVER}")"
    fi

    pacman -Sy --noconfirm
    repo_msg "nemesis_repo active."
    return 0
}
