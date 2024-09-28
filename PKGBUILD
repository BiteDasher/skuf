# Maintainer: Artemy Sudakov <finziyr@yandex.ru>

pkgname=skuf
__mkinitcpio_base=39.2
pkgver="27.0+${__mkinitcpio_base}"
pkgrel=3
pkgdesc="SKUF Network Boot System"
arch=('any')
url='https://github.com/BiteDasher/skuf'
license=('custom:GPL AND NO LICENSE')
depends=('awk' 'mkinitcpio-busybox>=1.19.4-2' 'kmod' 'util-linux>=2.23' 'libarchive' 'coreutils'
        'bash' 'binutils' 'diffutils' 'findutils' 'grep' 'filesystem>=2011.10-1' 'zstd' 'systemd'
        'dhcpcd' 'iproute2' 'iputils' 'cifs-utils' 'procps-ng'
        'openssl' 'kbd' 'terminus-font' 'sed' 'tar')
makedepends=('asciidoc' 'patch')
optdepends=('gzip: Use gzip compression for the initramfs image'
            'xz: Use lzma or xz compression for the initramfs image'
            'bzip2: Use bzip2 compression for the initramfs image'
            'lzop: Use lzo compression for the initramfs image'
            'lz4: Use lz4 compression for the initramfs image'
            'mkinitcpio-nfs-utils: Support for root filesystem on NFS')
provides=("initramfs" "skuf-rd=$pkgver" "skuf-nbs=$pkgver" "mkinitcpio=$__mkinitcpio_base")
conflicts=('mkinitcpio')

install=skuf.install
backup=('etc/mkinitcpio.conf')
source=("file:///tmp/mkinitcpio.tar"
        "https://sources.archlinux.org/other/mkinitcpio/mkinitcpio-$__mkinitcpio_base.tar.xz"
        "0001-trigger.patch")
sha512sums=('SKIP'
            'e4ba9fe901da56bb116510ec0c6abeba5153e57d9545baccbc466932951b7f324aa75ef7cc3de87f966456b0365b17552f367411d62585d500e88dc5c815058b'
            'b21e3961294e80bedd89a7e332ab11fc3b83eebfaf58d8f658e30f7d9caf2f84f4934224173c70f111932de8538fa327f5f6bfe9576b11bcbaf84d2d5ad8e85d')

prepare() {
    pushd "mkinitcpio-$__mkinitcpio_base"
    patch -Np1 < ../0001-trigger.patch
    popd
}

package() {
    # mkinitcpio
    make -C "mkinitcpio-$__mkinitcpio_base" DESTDIR="$pkgdir" install
    # skuf
    pushd "skuf_src"
    set -x

    install -dm755 "$pkgdir"/usr/lib/initcpio/skuf_data
    install -m644 98-skuf-save-resolvconf.libalpm_hook "$pkgdir"/usr/share/libalpm/hooks/98-skuf-save-resolvconf.hook
    install -m644 99-skuf-restore-resolvconf.libalpm_hook "$pkgdir"/usr/share/libalpm/hooks/99-skuf-restore-resolvconf.hook
    install -m755 skuf_resolvconf.libalpm_script "$pkgdir"/usr/share/libalpm/scripts/skuf_resolvconf
    install -m644 -t "$pkgdir"/usr/lib/initcpio/skuf_data banner_usb banner_kexec vconsole.conf locale.conf rootfs.tar inputrc passwd group
    install -dm755 "$pkgdir"/usr/lib/initcpio/skuf_data/dhcp
    install -m555 -t "$pkgdir"/usr/lib/initcpio/skuf_data/dhcp ./dhcp/dhcpcd-run-hooks
    install -m644 -t "$pkgdir"/usr/lib/initcpio/skuf_data/dhcp ./dhcp/dhcpcd.conf
    install -m444 -t "$pkgdir"/usr/lib/initcpio/skuf_data/dhcp ./dhcp/hook-01-test
    install -m444 -t "$pkgdir"/usr/lib/initcpio/skuf_data/dhcp ./dhcp/hook-20-resolv.conf
    install -m444 -t "$pkgdir"/usr/lib/initcpio/skuf_data/dhcp ./dhcp/hook-30-hostname
    install -m644 -t "$pkgdir"/usr/lib/initcpio/skuf_data/dhcp ./dhcp/kdhcpcd.conf
    install -m644 -t "$pkgdir"/usr/lib/initcpio/skuf_data/dhcp ./dhcp/resolv.conf.tail
    install -m700 -t "$pkgdir"/usr/lib/initcpio/skuf_data init kinit
    install -m755 -t "$pkgdir"/usr/lib/initcpio/skuf_data notinit
    install -Dm755 skuf_host_binary "$pkgdir"/usr/bin/skuf
    echo "$pkgver" | install -Dm644 /dev/stdin "$pkgdir"/usr/lib/initcpio/skuf_data/skuf_version
    for __xfile in ./hooks/*; do
        install -m644 -t "$pkgdir"/usr/lib/initcpio/hooks "$__xfile"
    done
    for __xfile in ./install/*; do
        install -m644 -t "$pkgdir"/usr/lib/initcpio/install "$__xfile"
    done
    install -m644 mkinitcpio.conf "$pkgdir"/etc/mkinitcpio.conf
    install -m644 hook.preset "$pkgdir"/usr/share/mkinitcpio/hook.preset
    install -Dm644 skuf-dummy-network-trigger.service "$pkgdir"/usr/lib/systemd/system/skuf-dummy-network-trigger.service
    if [ -f ./10-skuf.systemd_preset ]; then
        install -Dm644 10-skuf.systemd_preset "$pkgdir"/usr/lib/systemd/system-preset/10-skuf.preset
    fi

    set +x
    popd
}

# vim: set ft=sh ts=4 sw=4 et:
