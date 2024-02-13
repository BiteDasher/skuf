#!/bin/bash
if [ "$(id -u)" -ne 0 ]; then
    echo "You should execute this script as root" >&2
    exit 1
fi

if ! command -v mkarchiso &>/dev/null; then
    echo "Error: command 'mkarchiso' not found" >&2
    exit 1
fi

if ! command -v pacman-conf &>/dev/null; then
    echo "Error: command 'pacman-conf' not found" >&2
    exit 1
fi

if [ ! -d ./skuf_archiso ]; then
    echo "Error: directory 'skuf_archiso' does not exists" >&2
    exit 1
fi

if [ ! -d ./work ]; then
    echo "Error: directory 'work' does not exists" >&2
    exit 1
fi

if [ ! -d /tmp/repo ]; then
    echo "Error: directory '/tmp/repo' does not exists" >&2
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

if [ ! -f /tmp/repo/"$thispkgname" ]; then
    echo "Error: package does not exists in /tmp/repo"
    exit 1
fi

set -e
set -x
rm -f ./work/mkarchiso
set +e
set +x

if grep -o '^[[:blank:]]*mksquashfs "\$@" "\${image_path}" -noappend "\${airootfs_image_tool_options\[@\]}" "\${mksquashfs_options\[@\]}"' -- "$(command -v mkarchiso)" &>/dev/null; then
    cp -a -- "$(command -v mkarchiso)" ./work/mkarchiso
    sed -i 's/\(^[[:blank:]]*\)mksquashfs "\$@" "\${image_path}" -noappend "\${airootfs_image_tool_options\[@\]}" "\${mksquashfs_options\[@\]}"/\1:/' ./work/mkarchiso
else
    echo "Attention: the 'mkarchiso' executable is missing the line responsible for creating airootfs. The 'mkarchiso' file may have been updated and this line has been replaced with another one. The possible result of this action is in increase the size of the image by approximately 5 times. If you agree to the possible consequences - continue. If not, press Ctrl+C in next 15 seconds."
    echo "Missing line:"
    echo 'mksquashfs "$@" "${image_path}" -noappend "${airootfs_image_tool_options[@]}" "${mksquashfs_options[@]}"'
    echo "Problem file:"
    command -v mkarchiso
    sleep 15
    cp -a -- "$(command -v mkarchiso)" ./work/mkarchiso
fi

set -e
set -x
rm -r -f ./work/iso

install -d -m 755 ./work/iso

pacman_cachedir="$(pacman-conf CacheDir)"
if [ -z "$pacman_cachedir" ]; then
    pacman_cachedir=/var/cache/pacman/pkg/
fi
case "$pacman_cachedir" in
    */) : ;;
    *)  pacman_cachedir="${pacman_cachedir}/" ;;
esac
ln -sf /tmp/repo/"$thispkgname" -- "${pacman_cachedir}${thispkgname}"

./work/mkarchiso -v -w ./work/iso -o ./ ./skuf_archiso

rm -f -- "${pacman_cachedir}${thispkgname}"

echo "Done."

# vim: set ft=sh ts=4 sw=4 et:
