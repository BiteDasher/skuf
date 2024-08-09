#!/bin/bash
if [ "$(id -u)" -ne 0 ]; then
    echo "You should execute this script as root" >&2
    exit 1
fi

if ! command -v repo-add &>/dev/null; then
    echo "Error: command 'repo-add' not found" >&2
    exit 1
fi

if [ ! -d ./work ]; then
    echo "Error: directory 'work' does not exists" >&2
    exit 1
fi

if [ ! -r ./.pkgname ]; then
    echo "Error: file '.pkgname' does not exists or missing permissions" >&2
    exit 1
fi

if [ -z "$(cat ./.pkgname)" ]; then
	echo "Error: file '.pkgname' is empty" >&2
	exit 1
fi

thispkgname="$(cat ./.pkgname)"

if [ ! -f ./"$thispkgname" ]; then
    echo "Error: package does not exists" >&2
    exit 1
fi

set -e
set -x
rm -r -f ./work/repo
rm -r -f /tmp/repo

backtome="$(realpath .)"

install -d -m 755 ./work/repo
install -d -m 755 /tmp/repo
cp -a ./"$thispkgname" ./work/repo/

pushd ./work/repo
repo-add asshole.db.tar *
cp -a * /tmp/repo/
popd

echo "Done."

# vim: set ft=sh ts=4 sw=4 et:
