#!/bin/bash
if ! pacman -Q musl &>/dev/null; then
    echo "Error: package 'musl' not found" >&2
    exit 1
fi

if ! command -v make &>/dev/null; then
    echo "Error: command 'make' not found" >&2
    exit 1
fi

if ! command -v strip &>/dev/null; then
    echo "Error: package 'binutils' not found" >&2
    exit 1
fi

if ! command -v tar &>/dev/null; then
    echo "Error: command 'tar' not found" >&2
    exit 1
fi

if ! command -v curl &>/dev/null; then
    echo "Error: command 'curl' not found" >&2
    exit 1
fi

if [ -e /usr/include/linux       ] && \
   [ -e /usr/include/asm         ] && \
   [ -e /usr/include/asm-generic ]; then
    :
else
    echo "Error: package 'linux-api-headers' not found" >&2
    exit 1
fi

if [ -e /usr/lib/musl/include/linux       ] && \
   [ -e /usr/lib/musl/include/asm         ] && \
   [ -e /usr/lib/musl/include/asm-generic ]; then
    :
else
    echo "Error: package 'kernel-headers-musl' not found" >&2
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

if [ ! -f ./busybox_config ]; then
    echo "Error: file 'busybox_config' does not exists" >&2
    exit 1
fi

for __patches in ./busybox_*.patch ./kexec-tools_*.patch; do
    [ -e "$__patches" ] || continue
    if command -v patch &>/dev/null; then
        break
    else
        echo "Error: .patch files are found, but the 'patch' command is not" >&2
        exit 1
    fi
done

set -e
set -x
rm -r -f ./work/{busybox,kexec,rootfs}
rm -f ./skuf_src/rootfs.tar

ver_busybox=1.36.1
ver_kexec=2.0.28

if [ -n "$CC" ]; then
    if ! command -v "$CC" &>/dev/null; then
        echo "Error: command '$CC' not found" >&2
        exit 1
    fi
    muslCC="$CC"
elif command -v musl-clang &>/dev/null && command -v clang &>/dev/null; then
    CC=clang
    muslCC=musl-clang
elif command -v musl-gcc &>/dev/null && command -v gcc &>/dev/null; then
    CC=gcc
    muslCC=musl-gcc
else
    echo "Error: commands 'musl-gcc' and 'gcc' not found" >&2
    exit 1
fi

backtome="$(realpath .)"
##################################################
echo "[] Creating directory structure"
sleep 1
install -d -m 755 ./work/rootfs
install -d -m 755 ./work/rootfs/bin
install -d -m 755 ./work/rootfs/dev
install -d -m 755 ./work/rootfs/etc
install -d -m 755 ./work/rootfs/proc
install -d -m 700 ./work/rootfs/root
install -d -m 755 ./work/rootfs/run
install -d -m 755 ./work/rootfs/sys
install -d -m 755 ./work/rootfs/tmp
install -d -m 755 ./work/rootfs/var
ln -s /run ./work/rootfs/var/run

: > ./work/rootfs/init
chmod 755 ./work/rootfs/init
cat <<EOF > ./work/rootfs/init
#!/bin/ash

EOF
##################################################
echo "[] Building busybox $ver_busybox"
sleep 1
install -d -m 755 ./work/busybox

pushd ./work/busybox

curl -L -o ./busybox-$ver_busybox.tar.bz2 "https://busybox.net/downloads/busybox-$ver_busybox.tar.bz2"
tar -x -p -f ./busybox-$ver_busybox.tar.bz2

pushd ./busybox-$ver_busybox

install -m 644 "$backtome"/busybox_config ./.config

for bpatch in "$backtome"/busybox_*.patch; do
    [ -e "$bpatch" ] || continue
    patch -Np1 -i "$bpatch"
done

KCONFIG_NOTIMESTAMP=1 make CC="$muslCC"

install -m 755 ./busybox "$backtome"/work/rootfs/bin/busybox

popd
popd
##################################################
echo "[] Building kexec $ver_kexec"
sleep 1
install -d -m 755 ./work/kexec

pushd ./work/kexec

curl -L -o ./kexec-$ver_kexec.tar.gz "https://git.kernel.org/pub/scm/utils/kernel/kexec/kexec-tools.git/snapshot/kexec-tools-$ver_kexec.tar.gz"
tar -x -p -f ./kexec-$ver_kexec.tar.gz

pushd ./kexec-tools-$ver_kexec

for kpatch in "$backtome"/kexec-tools_*.patch; do
    [ -e "$kpatch" ] || continue
    patch -Np1 -i "$kpatch"
done

./bootstrap
CFLAGS+=" -mtune=generic"
CFLAGS="$CFLAGS" LDFLAGS=-static CC="$CC" ./configure
make

install -m 755 ./build/sbin/kexec "$backtome"/work/rootfs/bin/kexec

popd
popd
##################################################
echo "[] Striping"
sleep 1
pushd ./work/rootfs/bin

strip -S --strip-unneeded --remove-section=.note.gnu.gold-version --remove-section=.comment --remove-section=.note --remove-section=.note.gnu.build-id --remove-section=.note.ABI-tag ./busybox
strip -S --strip-unneeded --remove-section=.note.gnu.gold-version --remove-section=.comment --remove-section=.note --remove-section=.note.gnu.build-id --remove-section=.note.ABI-tag ./kexec

popd
##################################################
echo "[] Creating busybox symlinks"
sleep 1
pushd ./work/rootfs/bin

for applet in $(./busybox --list); do
    ln -s busybox ./"$applet"
done

popd

echo "[] rootfs.tar creation"
sleep 1
pushd ./work/rootfs

tar --create * --numeric-owner --owner=0 --group=0 --format=ustar -f "$backtome"/skuf_src/rootfs.tar

popd
##################################################
echo "Done."

# vim: set ft=sh ts=4 sw=4 et:
