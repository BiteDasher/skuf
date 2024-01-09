#!/bin/bash
if [ "$(id -u)" -ne 0 ]; then
    echo "You should execute this script as root" >&2
    exit 1
fi

if [ ! -d ./work ]; then
    echo "Error: directory 'work' does not exists" >&2
    exit 1
fi

set -e
set -x

rm -f /tmp/mkinitcpio.tar
rm -r -f /tmp/repo
rm -r -f -- ./work/*
rm -f ./skuf_src/{rootfs.tar,init,kinit}
rm -f ./.pkgname
rm -f ./.tune_*
rm -f ./.defaults_mark

# vim: set ft=sh ts=4 sw=4 et:
