![skuf](git_extras/skuf.png)
# SKUF - Suckless Kexec Using Fileshare 

> Ever wanted to be able to boot Linux[^1] over the network using an Ethernet cable but without setting up a PXE? Now you only need a SMB server that can be installed anywhere!

**SKUF Network Boot System** allows you to boot the [Arch Linux](https://archlinux.org)[^2] operating system on a computer connected to network via Ethernet using USB flash drive (100MB minimum) and a SMB file share.

> [!CAUTION]
> **The only supported distribution is Arch Linux™.** Other shitty systems like Debian, Ubuntu, Manjaro, Fedora, openSUSE, etc. are NOT supported and NEVER WILL BE.


## Requirements

Two computers in the same network:

**Server**:
- [x] Running SMB file server
- [x] Your user on the SMB server **has a password**. Users without password or anonymous access **are not supported** 

**Client**:
- [x] Connected to network via Ethernet cable. Wireless is not supported.
- [x] A USB stick/CD/DVD with the `skuflinux` image (you can also use [Ventoy](https://www.ventoy.net))
- [x] Brain not poisoned with beer so you have enough brain cells to read this manual

> [!CAUTION]
> **Prebuilt binaries and ISO images will NEVER be available** due to possible security risks. Read the build instructions carefully.

## Scheme of work
> [!NOTE] 
> The example illustrates how the `server` and `client` work together. <br>
> **Server** — a computer with the `SMB` server running. <br>
> **Client** — a computer that will boot the system from the `server` over the network using a cable <br>

You have a USB flash drive/CD/DVD with an ISO image of `skuflinux` on it. You have two PCs in your room/college/office. First one is the one you will be sitting at. The other one is running SMB server with a directory that **you have write access to**. That directory contains filesystem image with the Arch Linux distribution and the `skuf` package installed.

### Step 1: Loading kernel and initramfs from SMB server
After booting from USB drive with `skuflinux` you will be prompted to enter SMB server address and port, user credentials and path to filesystem image. Now SKUF script will do the following:

- Obtain an IP address using `dhcpcd`
- Mount the SMB directory
- Mount the image volume with Arch Linux
- Generate an encrypted string with your answers to the questions asked earlier
- Load kernel and initramfs from a previously mounted Arch Linux image into RAM
- Unmount SMB and image volume with Arch Linux
- Execute [kexec](https://wiki.archlinux.org/title/kexec)

### Step 2: Re-mounting SMB and running system
Now when the kernel and initramfs of your Arch Linux were loaded from SMB server, SKUF mounts system image again:

- The newly booted system obtaining IP address again
- The previously encrypted string contained your answers to the questions. It was passed to the kernel command line (`/proc/cmdline`) in encrypted form, and will now be decrypted, so you don't have to write it all over again.
- Mounting the SMB directory again
- Once the Arch Linux image volume is mounted, SKUF executes [switch_root](https://man.archlinux.org/man/switch_root.8.en) and system is booted. Congratulations!


## Building

> [!CAUTION]
> **The only supported distribution is Arch Linux™.** Other shitty systems like Debian, Ubuntu, Manjaro, Fedora, openSUSE, etc. are NOT supported and NEVER WILL BE.

### Required packages
- `arch-install-scripts`
- `archiso`
- `base`
- `base-devel`
- `binutils`
- `clang` or `gcc`
- `musl`
- `kernel-api-headers`
- `kernel-headers-musl`

###  Build instructions

Clone this repository using git:
```
git clone https://github.com/BiteDasher/skuf
cd skuf
```

Tune encryption obfuscation and encryption password (see [Customization instructions](#Password-tuning)):
```
vim tune.password
vim tune.crypt
```

Setup defaults for `ISO` (optional):
```
vim defaults
```

Run configuraion sripts:
```
./tune_crypt.sh
./tune_password.sh
./setup_defaults.sh
```

Build SKUF:
```
./build_rootfs_tar.sh
./build_package.sh
./setup_repo.sh
./build_iso.sh
./create_image.sh SIZE_IN_GIGABYTES additional_packages
```

> [!NOTE]
> Basic installation of Arch Linux without GUI or any additional software takes about 1 GB.

Done! 💪🎉 Now write `skuflinux-smth.iso` to your USB drive, put `arch.ext4` into your directory on SMB server and try SKUF Network Boot System.


## Customisation instructions
### Password tuning
String for `/proc/cmdline` is encrypted using [OpenSSL](https://www.openssl.org). You need to specify **encryption password** and **number of iterations** in the `tune.password` file in following format:
```
ITERATIONS_COUNT PASSWORD
```
> [!NOTE]
> For an example, see the `tune.passwordX` file

### Obfuscation tuning
String that is encrypted through [OpenSSL](https://www.openssl.org) is eventually turned into a [base64](https://en.m.wikipedia.org/wiki/Base64) string. You can obfuscate this string by swapping these letters. Write **pairs of letters** in the following format to the `tune.crypt` file:
```
A B
X Y
I O
```
> [!NOTE]
> For an example, see the `tune.cryptX` file

### Defaults setup
When you booted up the `skuflinux` ISO image from your media device, you will be asked questions like: SMB server address, SMB server port, SMB protocol version and so on. Edit the `defaults` file if you want to preset them manually.

Table of SKUF variables:
|Variable|Meaning|
|:---|:---|
|`SAMBA_ADDRESS`|Address of the SMB server where the client directory with the `Arch Linux` image is located|
|`SAMBA_PORT`|SMB server port|
|`SAMBA_VERSION`|SMB server protocol version|
|`SAMBA_DOMAIN`|Domain for the SMB server (default domain is `WORKGROUP`)|
|`VOLUME_PATH`|Path to the directory on the SMB server where the client Arch Linux image volume and swap file are located(see [Tips and Tricks](#tips-and-tricks))|
|`VOLUME_FILENAME`|Arch Linux image volume name that is located in `VOLUME_PATH`|
|`SWAP_FILENAME`|swap file name that is located in `VOLUME_PATH`|
|`SAMBA_EXTRA_MOUNT_OPTS`|Additional SMB mount options. Applies to both [step 1](#Step-1-Loading-kernel-and-initramfs-from-SMB-server) and [step 2](#Step-2-Re-mounting-SMB-and-running-system) of SKUF boot process.|
|`VOLUME_EXTRA_MOUNT_OPTS`|Additional client Arch Linux image volume mount options. Applies to both [step 1](#Step-1-Loading-kernel-and-initramfs-from-SMB-server) and [step 2](#Step-2-Re-mounting-SMB-and-running-system) of SKUF boot process.|
|`CHECK_FS`|Whether to check the integrity of a file system image with Arch Linux. Accepts `Yes` or `No`. Applies only to [step 2](#Step-2-Re-mounting-SMB-and-running-system).|
|`EXTRA_KERNEL_OPTS`|Additional linux kernel options|
|`PATH_TO_NEW_KERNEL`|Path to the new kernel that will be loaded using kexec. The new kernel must be in the Arch Linux image that is lies on SMB server|
|`PATH_TO_NEW_INITRAMFS`|Path to the new initramfs that will be loaded using kexec alongside kernel. The new initramfs must be in the Arch Linux image that is lies on SMB server|
|`MAX_SMB_RETRY_COUNT`|Maximum number of attempts to re-enter SMB credentials if the first mount attempt failed. Applies only to [step 1](#Step-1-Loading-kernel-and-initramfs-from-SMB-server). (default value: `2`)|

## Tips and Tricks
- You can place a swap file next to the Arch Linux image volume so you can use it on your system. The swap file will be connected over the network as a loop device.

- You can use [Plymouth](https://wiki.archlinux.org/title/plymouth) in [step 2](#Step-2-Re-mounting-SMB-and-running-system). Add `splash` to `EXTRA_KERNEL_OPTS` to the `defaults` file, also don't forget to add `HOOKS=(... plymouth ...)` to the `skuf_src/mkinitcpio.conf` and install `plymouth` package.

- In [step 1](#Step-1-Loading-kernel-and-initramfs-from-SMB-server), you can write `@u@` and `@fu@` in the path to the client(your) directory, in the path to the image volume file and in the swap file. If you login as `john@corp.domain`, `@u@` will be `john` and `@fu@` will be `john@corp.domain`.

- After building the ISO image and creating a file system image with Arch Linux you can execute `sudo ./clean.sh` to remove unnedeed files.

- Password for `root` and `test` users in `arch.ext4` is `0000`

- If you enter something incorrectly while entering SMB address, kernel path, etc. at [step 1](#Step-1-Loading-kernel-and-initramfs-from-SMB-server) and fall into the interactive shell, write `reboot -f`. No, **you cannot restart the script**. Train your attention.

- If the client computer has `UEFI`, you can install `SKUF` on a `FAT32 EFI` partition so you don't have to use a USB flash drive/CD/DVD. To do this, mount `skuflinux-smth.iso` somewhere (like /mnt), then copy `/mnt/skuf/boot/x86_64/{vmlinuz-linux,initramfs-linux.img}` to `FAT32 EFI` partition and execute `efibootmgr -c -d /dev/sdX -p Y -u 'initrd=\initramfs-linux.img' -l '\vmlinuz-linux' -L 'SKUF'` where */dev/sdX* is the target disk and *Y* is the target `FAT32 EFI` partition number.

## Demonstration

https://github.com/BiteDasher/skuf/assets/48867887/79a5b40d-7a48-4046-a857-aa300a57e137

## Afterword
Huge thanks to the Arch Linux development team for their awesome distribution and [mkarchiso](https://gitlab.archlinux.org/archlinux/archiso) and [mkinitcpio](https://gitlab.archlinux.org/archlinux/mkinitcpio/mkinitcpio) utilities. They made the creation of this project much easier.

[^1]: The registered trademark Linux® is used pursuant to a sublicense from LMI, the exclusive licensee of Linus Torvalds, owner of the mark on a world-wide basis.
[^2]:Copyright © 2002-2024 Judd Vinet, Aaron Griffin and Levente Polyák.
  The Arch Linux name and logo are recognized trademarks. Some rights reserved.
