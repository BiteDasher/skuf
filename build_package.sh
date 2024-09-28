#!/bin/bash
if ! command -v makepkg &>/dev/null; then
    echo "Error: command 'makepkg' not found" >&2
    exit 1
fi

if ! command -v tar &>/dev/null; then
    echo "Error: command 'tar' not found" >&2
    exit 1
fi

if [ ! -d ./work ]; then
    echo "Error: directory 'work' does not exists" >&2
    exit 1
fi

if [ ! -d ./skuf_src ]; then
    echo "Error: directory 'skuf_src' does not exists" >&2
    exit 1
fi

if [ ! -r ./.defaults_mark ]; then
    echo "Error: defaults not applied" >&2
    exit 1
fi

if [ -f ./skuf_src/rootfs.tar ] && \
   [ -f ./skuf_src/kinit      ] && \
   [ -f ./skuf_src/init       ]; then
    :
else
    echo "Error: package not ready" >&2
    exit 1
fi

set -e
set -x
rm -r -f ./work/package
rm -f /tmp/mkinitcpio.tar

backtome="$(realpath .)"

install -d -m 755 ./work/package
tar --create ./skuf_src --numeric-owner --owner=0 --group=0 --format=ustar -f /tmp/mkinitcpio.tar
install -m 644 ./PKGBUILD ./work/package/PKGBUILD
install -m 644 ./skuf.install ./work/package/skuf.install
# https://gitlab.archlinux.org/archlinux/packaging/packages/mkinitcpio/-/raw/6cf9c3b8932c29d3f62d4a3d24fe79bdab35e83b/0001-trigger.patch?inline=false
install -m 644 ./0001-trigger.patch ./work/package/0001-trigger.patch
pushd ./work/package
makepkg -sr --noconfirm

for pkg in skuf-*.pkg.tar*; do
    [ "$pkg" == 'skuf-*.pkg.tar*' ] && exit 1 || break
done

install -m 600 "$pkg" "$backtome"/"$pkg"
echo "$pkg" > "$backtome"/.pkgname

popd

echo "Done."

# vim: set ft=sh ts=4 sw=4 et:
