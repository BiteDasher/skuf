# Maintainer: Artemy Sudakov <finziyr@yandex.ru>

pkgname=skuf
__mkinitcpio_base=37.3
pkgver="13.0+${__mkinitcpio_base}"
pkgrel=1
pkgdesc="SKUF Network Boot System"
arch=('any')
url='https://github.com/BiteDasher/skuf'
license=('custom:GPL AND NO LICENSE')
depends=('awk' 'mkinitcpio-busybox>=1.19.4-2' 'kmod' 'util-linux>=2.23' 'libarchive' 'coreutils'
        'bash' 'binutils' 'diffutils' 'findutils' 'grep' 'filesystem>=2011.10-1' 'zstd' 'systemd'
        'dhcpcd' 'iproute2' 'iputils' 'cifs-utils' 'procps-ng'
        'openssl' 'kbd' 'terminus-font' 'sed' 'tar')
makedepends=('asciidoc')
optdepends=('gzip: Use gzip compression for the initramfs image'
            'xz: Use lzma or xz compression for the initramfs image'
            'bzip2: Use bzip2 compression for the initramfs image'
            'lzop: Use lzo compression for the initramfs image'
            'lz4: Use lz4 compression for the initramfs image'
            'mkinitcpio-nfs-utils: Support for root filesystem on NFS')
provides=("initramfs" "skuf-rd=$pkgver" "skuf-nbs=$pkgver" "mkinitcpio=$__mkinitcpio_base")
conflicts=('mkinitcpio')
backup=('etc/mkinitcpio.conf')
source=("file:///tmp/mkinitcpio.tar"
        "https://sources.archlinux.org/other/mkinitcpio/mkinitcpio-$__mkinitcpio_base.tar.gz")
sha512sums=('SKIP'
            'edee8dfbc452a0fc6ca9e8c7321beffa4463e504641b99a8d08ab9df665b697a0192f7760994b9917f34ba83d15543dedd3c4690364663b4534724a06a262db7')

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
    for __xfile in ./hooks/*; do
        install -m644 -t "$pkgdir"/usr/lib/initcpio/hooks "$__xfile"
    done
    for __xfile in ./install/*; do
        install -m644 -t "$pkgdir"/usr/lib/initcpio/install "$__xfile"
    done
    install -m644 mkinitcpio.conf "$pkgdir"/etc/mkinitcpio.conf
    install -m644 hook.preset "$pkgdir"/usr/share/mkinitcpio/hook.preset

    set +x
    popd
}

# vim: set ft=sh ts=4 sw=4 et:
