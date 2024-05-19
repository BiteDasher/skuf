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

if grep -o -- '^[[:space:]]*mksquashfs "\$@" "\${image_path}" -noappend "\${airootfs_image_tool_options\[@\]}" "\${mksquashfs_options\[@\]}"' "$(command -v mkarchiso)" &>/dev/null; then
    cp -a -- "$(command -v mkarchiso)" ./work/mkarchiso
    sed -i 's/\(^[[:space:]]*\)mksquashfs "\$@" "\${image_path}" -noappend "\${airootfs_image_tool_options\[@\]}" "\${mksquashfs_options\[@\]}"/\1: /' ./work/mkarchiso
else
    echo -e "\e[1;33mAttention\e[0m: the '\e[1mmkarchiso\e[0m' executable is missing the line responsible for creating airootfs. The '\e[1mmkarchiso\e[0m' file may have been updated and this line has been replaced with another one. The possible result of this action is \e[0;33min increase the size of the image by\e[0m \e[1;33mapproximately 5 times\e[0m. If you agree to the possible consequences - continue. If not, press \e[1mCtrl+C\e[0m in next \e[1m15 seconds\e[0m."
    echo ""
    echo -e "\e[1mMissing line:\e[0m"
    echo 'mksquashfs "$@" "${image_path}" -noappend "${airootfs_image_tool_options[@]}" "${mksquashfs_options[@]}"'
    echo -e "\e[1mProblem file:\e[0m"
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
ln -sf -- /tmp/repo/"$thispkgname" "${pacman_cachedir}${thispkgname}"

./work/mkarchiso -v -w ./work/iso -o ./ ./skuf_archiso

rm -f -- "${pacman_cachedir}${thispkgname}"

echo "Done."

# vim: set ft=sh ts=4 sw=4 et:
