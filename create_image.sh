#!/bin/bash
if [ "$(id -u)" -ne 0 ]; then
    echo "You should execute this script as root" >&2
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

if ! command -v mkfs.ext4 &>/dev/null; then
    echo "Error: command 'mkfs.ext4' not found" >&2
    exit 1
fi

if ! command -v dd &>/dev/null; then
    echo "Error: command 'dd' not found" >&2
    exit 1
fi

if ! command -v pacman-conf &>/dev/null; then
    echo "Error: command 'pacman-conf' not found" >&2
    exit 1
fi

if ! pacman -Q arch-install-scripts &>/dev/null || ! command -v pacstrap &>/dev/null; then
    echo "Error: package 'arch-install-scripts' not found" >&2
    exit 1
fi

if ! command -v arch-chroot &>/dev/null; then
    echo "Error: command 'arch-chroot' not found" >&2
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

if [ -z "$1" ]; then
    echo "Error: image size not specified (1 argument)" >&2
    exit 1
fi

case "$1" in
    '-s'|'-S'|'--sparse'|'--sparse-file')
        SPARSE=1
        filetype="sparse"
        shift
    ;;
    *)
        SPARSE=0
        filetype="empty"
    ;;
esac

case "$1" in
    ''|*[!0-9]*)
        echo "size containts something other than number!" >&2
        exit 1
    ;;
    0*)
        echo "size argument should not start with 0!" >&2
        exit 1
    ;;
    *)
        :
    ;;
esac

if [ ! -d /mnt ]; then
    echo "Error: directory '/mnt' does not exists" >&2
    exit 1
fi

image_size="$1"
shift

set -e
set -x
rm -r -f ./arch.ext4

block_size="8M"

count_times=$((image_size * 1000 / 8))

backtome="$(realpath .)"
##################################################
echo "[] Creating $filetype file"
sleep 1
if [ "$SPARSE" == 1 ]; then
    dd if=/dev/zero of=./arch.ext4 bs="1" count="0" seek="${image_size}G" status=progress
else
    dd if=/dev/zero of=./arch.ext4 bs="$block_size" count="$count_times" status=progress
fi
#################################################
echo "[] Creating ext4 filesystem"
sleep 1
mkfs.ext4 ./arch.ext4
##################################################
echo "[] Mounting image to /mnt (don't worry if you have something mounted over there)"
sleep 3
mount ./arch.ext4 /mnt
##################################################
echo "[] Modifying /etc/pacman.conf"
sleep 1
cp -a /etc/pacman.conf ./work/pacman.conf
cat <<EOF >> ./work/pacman.conf
[asshole]
SigLevel = Optional
Server = file:///tmp/repo
EOF
##################################################
echo "[] Creating symlink to skuf package in pacman CacheDir"
sleep 1
pacman_cachedir="$(pacman-conf CacheDir)"
if [ -z "$pacman_cachedir" ]; then
    pacman_cachedir=/var/cache/pacman/pkg/
fi
case "$pacman_cachedir" in
    */) : ;;
    *)  pacman_cachedir="${pacman_cachedir}/" ;;
esac
ln -sf /tmp/repo/"$thispkgname" -- "${pacman_cachedir}${thispkgname}"
##################################################
echo "[] Installing packages to image"
sleep 3
pacstrap -c -C ./work/pacman.conf /mnt base sudo linux linux-firmware skuf vim "$@"
rm -f -- "${pacman_cachedir}${thispkgname}"
rm -f ./work/pacman.conf
##################################################
echo "[] Creating temporary script"
sleep 1
cat <<EOF > /mnt/skuf_afterwork
#!/usr/bin/env bash
echo "skuf" > /etc/hostname
echo "127.0.0.1 localhost" >> /etc/hosts
echo "::1 localhost" >> /etc/hosts
echo "root:0000" | chpasswd --crypt-method SHA512
useradd -m -u 1005 -U -G wheel,video,audio -s /bin/bash test
echo "test:0000" | chpasswd --crypt-method SHA512
sed 's/^# %wheel ALL=(ALL:ALL) NOPASSWD: ALL/%wheel ALL=(ALL:ALL) NOPASSWD: ALL/' -i /etc/sudoers
echo "LANG=C.UTF-8" > /etc/locale.conf
EOF
chmod 700 /mnt/skuf_afterwork
##################################################
echo "[] Executing temporary script"
sleep 1
arch-chroot /mnt /skuf_afterwork
rm -f /mnt/skuf_afterwork
##################################################
echo "[] Unmounting /mnt"
umount /mnt
sleep 1
##################################################
echo "Done."

# vim: set ft=sh ts=4 sw=4 et:
