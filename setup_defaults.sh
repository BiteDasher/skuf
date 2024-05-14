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

sed_prepare() {
    local line to_append

    line="$(grep -o "^$1=.*$" ./defaults)" || :
    to_append="${line#*=}"
    echo "preset_$2=$to_append" >> ./.setup_defaults_temp
}

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

[ -f ./defaults ] && sh -n ./defaults

: >./.setup_defaults_temp

sed_prepare SAMBA_USERNAME          smbusername
sed_prepare SAMBA_PASSWORD          smbpassword
sed_prepare SAMBA_ADDRESS           smbaddr
sed_prepare SAMBA_PORT              smbport
sed_prepare SAMBA_VERSION           smbversion
sed_prepare SAMBA_DOMAIN            smbdomain
sed_prepare VOLUME_PATH             smbvolumepath
sed_prepare VOLUME_FILENAME         smbvolumefilename
sed_prepare SWAP_FILENAME           smbswapfilename
sed_prepare SAMBA_EXTRA_MOUNT_OPTS  smbmountopts
sed_prepare VOLUME_EXTRA_MOUNT_OPTS newrootmountopts
sed_prepare CHECK_FS                newrootfsck
sed_prepare EXTRA_KERNEL_OPTS       kernelopts
sed_prepare PATH_TO_NEW_KERNEL      kernelpath
sed_prepare PATH_TO_NEW_INITRAMFS   initramfspath
sed_prepare MAX_SMB_RETRY_COUNT     smbretry
sed_prepare SKIP                    skip

sed -i '
    /^# SKUF_PRESETS_START #$/,/^# SKUF_PRESETS_END #$/{
        /^# SKUF_PRESETS_START #$/{
            n
            r ./.setup_defaults_temp
        }
        /^# SKUF_PRESETS_END #$/!d
   }
' ./skuf_src/kinit

rm ./.setup_defaults_temp

: > ./.defaults_mark

echo "Done."

# vim: set ft=sh ts=4 sw=4 et:
