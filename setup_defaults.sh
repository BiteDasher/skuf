#!/bin/bash
if [ ! -f "./skuf_src/init(untuned)" ]; then
    echo "Error: file 'skuf_src/init(untuned)' does not exists" >&2
    exit 1
fi

if [ ! -f "./skuf_src/kinit(untuned)" ]; then
    echo "Error: file 'skuf_src/kinit(untuned)' does not exists" >&2
    exit 1
fi

set -e
set -x
rm -f ./.defaults_mark

[ -f ./skuf_src/kinit ] || cp -a "./skuf_src/kinit(untuned)" "./skuf_src/kinit"

SAMBA_ADDRESS=""
SAMBA_PORT=""
SAMBA_VERSION=""
SAMBA_DOMAIN=""
VOLUME_PATH=""
VOLUME_FILENAME=""
SWAP_FILENAME=""
SAMBA_EXTRA_MOUNT_OPTS=""
VOLUME_EXTRA_MOUNT_OPTS=""
CHECK_FS=""
EXTRA_KERNEL_OPTS=""
PATH_TO_NEW_KERNEL=""
PATH_TO_NEW_INITRAMFS=""
MAX_SMB_RETRY_COUNT=""

if [ -f ./defaults ]; then
    if [ -r ./defaults ]; then
        if [ -z "$(cat ./defaults)" ]; then
	        echo "Warning: file 'defaults' is empty" >&2
        fi
    else
        echo "Error: file 'defaults' missing permissions" >&2
        exit 1
    fi
fi

[ -f ./defaults ] && source ./defaults

# "'" - very cool! Thanks, GNU!
if [ -n "$SAMBA_ADDRESS" ]; then
    sed -i 's|# SAMBA_ADDRESS #|-i "'"$SAMBA_ADDRESS"'" smbaddr|' ./skuf_src/kinit
else
    sed -i 's|# SAMBA_ADDRESS #|smbaddr|' ./skuf_src/kinit
fi
##################################################
if [ -n "$SAMBA_PORT" ]; then
    sed -i 's|# SAMBA_PORT #|-i "'"$SAMBA_PORT"'" smbport|' ./skuf_src/kinit
else
    sed -i 's|# SAMBA_PORT #|smbport|' ./skuf_src/kinit
fi
##################################################
if [ -n "$SAMBA_VERSION" ]; then
    sed -i 's|# SAMBA_VERSION #|-i "'"$SAMBA_VERSION"'" smbversion|' ./skuf_src/kinit
else
    sed -i 's|# SAMBA_VERSION #|smbversion|' ./skuf_src/kinit
fi
##################################################
if [ -n "$SAMBA_DOMAIN" ]; then
    sed -i 's|# SAMBA_DOMAIN #|-i "'"$SAMBA_DOMAIN"'" smbdomain|' ./skuf_src/kinit
else
    sed -i 's|# SAMBA_DOMAIN #|smbdomain|' ./skuf_src/kinit
fi
##################################################
if [ -n "$VOLUME_PATH" ]; then
    sed -i 's|# VOLUME_PATH #|-i "'"$VOLUME_PATH"'" smbvolumepath|' ./skuf_src/kinit
else
    sed -i 's|# VOLUME_PATH #|smbvolumepath|' ./skuf_src/kinit
fi
##################################################
if [ -n "$VOLUME_FILENAME" ]; then
    sed -i 's|# VOLUME_FILENAME #|-i "'"$VOLUME_FILENAME"'" smbvolumefilename|' ./skuf_src/kinit
else
    sed -i 's|# VOLUME_FILENAME #|smbvolumefilename|' ./skuf_src/kinit
fi
##################################################
if [ -n "$SWAP_FILENAME" ]; then
    sed -i 's|# SWAP_FILENAME #|-i "'"$SWAP_FILENAME"'" smbswapfilename|' ./skuf_src/kinit
else
    sed -i 's|# SWAP_FILENAME #|smbswapfilename|' ./skuf_src/kinit
fi
##################################################
if [ -n "$SAMBA_EXTRA_MOUNT_OPTS" ]; then
    sed -i 's|# SAMBA_EXTRA_MOUNT_OPTS #|-i "'"$SWAP_EXTRA_MOUNT_OPTS"'" smbmountopts|' ./skuf_src/kinit
else
    sed -i 's|# SAMBA_EXTRA_MOUNT_OPTS #|smbmountopts|' ./skuf_src/kinit
fi
##################################################
if [ -n "$VOLUME_EXTRA_MOUNT_OPTS" ]; then
    sed -i 's|# VOLUME_EXTRA_MOUNT_OPTS #|-i "'"$VOLUME_EXTRA_MOUNT_OPTS"'" newrootmountopts|' ./skuf_src/kinit
else
    sed -i 's|# VOLUME_EXTRA_MOUNT_OPTS #|newrootmountopts|' ./skuf_src/kinit
fi
##################################################
if [ -n "$CHECK_FS" ]; then
    sed -i 's|# CHECK_FS #|-i "'"$CHECK_FS"'" newrootfsck|' ./skuf_src/kinit
else
    sed -i 's|# CHECK_FS #|newrootfsck|' ./skuf_src/kinit
fi
##################################################
if [ -n "$EXTRA_KERNEL_OPTS" ]; then
    sed -i 's|# EXTRA_KERNEL_OPTS #|-i "'"$EXTRA_KERNEL_OPTS"'" kernelopts|' ./skuf_src/kinit
else
    sed -i 's|# EXTRA_KERNEL_OPTS #|kernelopts|' ./skuf_src/kinit
fi
##################################################
if [ -n "$PATH_TO_NEW_KERNEL" ]; then
    sed -i 's|# PATH_TO_NEW_KERNEL #|-i "'"$PATH_TO_NEW_KERNEL"'" kernelpath|' ./skuf_src/kinit
else
    sed -i 's|# PATH_TO_NEW_KERNEL #|kernelpath|' ./skuf_src/kinit
fi
##################################################
if [ -n "$PATH_TO_NEW_INITRAMFS" ]; then
    sed -i 's|# PATH_TO_NEW_INITRAMFS #|-i "'"$PATH_TO_NEW_INITRAMFS"'" initramfspath|' ./skuf_src/kinit
else
    sed -i 's|# PATH_TO_NEW_INITRAMFS #|initramfspath|' ./skuf_src/kinit
fi
##################################################
if [ -n "$MAX_SMB_RETRY_COUNT" ]; then
    sed -i 's|if ! retry_samba; then$|if ! retry_samba '"$MAX_SMB_RETRY_COUNT"'; then|' ./skuf_src/kinit
fi

: > ./.defaults_mark

echo "Done."

# vim: set ft=sh ts=4 sw=4 et:
