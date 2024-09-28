#!/bin/bash
if [ "$(id -u)" -ne 0 ]; then
    echo "You should execute this script as root" >&2
    exit 1
fi

set -e
set -x

# $@ for possible ./install_deps.sh -y -u
pacman -S --noconfirm "$@" \
        arch-install-scripts \
        archiso \
        base \
        base-devel \
        binutils \
        musl \
        linux-api-headers \
        kernel-headers-musl \
        patch

if [ -n "$CC" ] && command -v "$CC" &>/dev/null; then
    :
elif ! command -v gcc &>/dev/null && ! command -v clang; then
    pacman -S clang
fi

echo "Done."

# vim: set ft=sh ts=4 sw=4 et:
