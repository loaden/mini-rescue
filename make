#!/bin/bash
#
# Mini Rescue Live System: Only Focus Recovery
# Copyright (C) 2021 Yuchen Deng [Zz] <loaden@gmail.com>
# QQ Group: 19346666, 111601117
#
# Redo Rescue: Backup and Recovery Made Easy <redorescue.com>
# Copyright (C) 2010-2020 Zebradots Software
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program. If not, see <http://www.gnu.org/licenses/>.
#

VER=0.9
BASE=buster
ARCH=amd64
ROOT=rootdir
FILE=setup.sh
USER=live
NONFREE=true
MIRROR=https://mirrors.tuna.tsinghua.edu.cn/debian
LANG="C"

# Set colored output codes
red='\e[1;31m'
wht='\e[1;37m'
yel='\e[1;33m'
off='\e[0m'

# Show title
echo -e "\n$off---------------------------"
echo -e "$wht  MINI RESCUE ISO CREATOR$off"
echo -e "       Version $VER"
echo -e "---------------------------\n"

# Check: Must be root
if [ "$EUID" -ne 0 ]
    then echo -e "$red* ERROR: Must be run as root.$off\n"
    exit
fi

# Check: No spaces in cwd
if [[ `pwd` == *" "* ]]
    then echo -e "$red* ERROR: Current absolute pathname contains a space.$off\n"
    exit
fi

# Get requested action
ACTION=$1

chroot_mount() {
    #
    # Execute system mounts
    #
    mount -t sysfs -o nodev,noexec,nosuid sysfs $ROOT/sys
    mount -t proc -o nodev,noexec,nosuid proc $ROOT/proc

    # Some things don't work properly without /etc/mtab.
    ln -sf $ROOT/proc/mounts $ROOT/etc/mtab

    # Note that this only becomes /dev on the real filesystem if udev's scripts
    # are used; which they will be, but it's worth pointing out
    if ! mount -t devtmpfs -o mode=0755 udev $ROOT/dev; then
        echo "W: devtmpfs not available, falling back to tmpfs for $ROOT/dev"
        mount -t tmpfs -o mode=0755 udev $ROOT/dev
        [ -e $ROOT/dev/console ] || mknod -m 0600 $ROOT/dev/console c 5 1
        [ -e $ROOT/dev/null ] || mknod $ROOT/dev/null c 1 3
    fi
    mkdir -p $ROOT/dev/pts
    mount -t devpts -o noexec,nosuid,gid=5,mode=0620 devpts $ROOT/dev/pts || true
    mount -t tmpfs -o "noexec,nosuid,size=10%,mode=0755" tmpfs $ROOT/run
    mkdir $ROOT/run/initramfs

    # Compatibility symlink for the pre-oneiric locations
    ln -sf $ROOT/run/initramfs $ROOT/dev/.initramfs
}

chroot_umount() {
    #
    # Execute system umounts
    #
    sleep 1
    umount -lf $ROOT/sys 2>/dev/null
    umount -lf $ROOT/proc 2>/dev/null
    umount -lf $ROOT/dev/pts 2>/dev/null
    umount -lf $ROOT/dev 2>/dev/null
    umount -lf $ROOT/run 2>/dev/null
    sleep 1
}

clean() {
    #
    # Remove all build files
    #
    chroot_umount
    rm -rf {image,scratch,$ROOT,*.iso}
    echo -e "$yel* All clean!$off\n"
    exit
}

prepare() {
    #
    # Prepare host environment
    #
    echo -e "$yel* Building from scratch.$off"
    chroot_umount
    rm -rf {image,scratch,$ROOT,*.iso}
    CACHE=debootstrap-$BASE-$ARCH.tar.zst
    if [ -f "$CACHE" ]; then
        echo -e "$yel* $CACHE exists, extracting existing archive...$off"
        sleep 2
        tar -xpvf $CACHE
    else
        echo -e "$yel* $CACHE does not exist, running debootstrap...$off"
        sleep 2
        apt install --yes --no-install-recommends debootstrap squashfs-tools mtools xorriso zstd
        rm -rf $ROOT
        mkdir -p $ROOT
        debootstrap --arch=$ARCH --variant=minbase --no-check-gpg $BASE $ROOT $MIRROR
        tar -I "zstd -T0" -capvf $CACHE $ROOT
    fi
}

script_init() {
    #
    # Setup script: Base configuration
    #
    cat > $ROOT/$FILE <<EOL
#!/bin/bash

# Set hostname
echo 'rescue' > /etc/hostname

# Set hosts
cat > /etc/hosts <<END
127.0.0.1  localhost
127.0.1.1  rescue
::1        localhost ip6-localhost ip6-loopback
ff02::1    ip6-allnodes
ff02::2    ip6-allrouters
END

# Set default locale
cat >> /etc/bash.bashrc <<END
export LANG="C"
export LC_ALL="C"
END

# Set modprobe env
export MODPROBE_OPTIONS="-qb"

# Export environment
export HOME=/root; export LANG=C; export LC_ALL=C;
EOL
}

script_base() {
    #
    # Setup script: Install packages
    #
    if [[ "$ARCH" == "i386" || "$ARCH" == "x86" ]]; then
        KERN="686"
    else
        KERN="amd64"
    fi
    cat >> $ROOT/$FILE <<EOL
# Install base packages
export DEBIAN_FRONTEND=noninteractive
apt install --yes --no-install-recommends \
    linux-image-$KERN firmware-linux-free live-boot sudo nano procps bash-completion

# Add regular user
useradd --create-home $USER --shell /bin/bash
adduser $USER sudo
echo '$USER:$USER' | chpasswd
EOL
}

script_desktop() {
    #
    # Setup script: Install desktop packages
    #
    cat >> $ROOT/$FILE <<EOL
# Install desktop packages
apt install --yes --no-install-recommends \
    \
    xserver-xorg xinit dbus-x11 blackbox bbpager lightdm \
    pcmanfm xarchiver unzip zstd lxterminal mousepad gpicview \
    network-manager \
    \
    gparted dosfstools exfat-fuse ntfs-3g btrfs-progs \
    \
    fonts-wqy-microhei rsync iputils-ping \
    \
    $EXTRA_PACKAGES
EOL
}

script_add_nonfree() {
    #
    # Setup script: Install non-free packages for hardware support
    #
    # Non-free firmware does not comply with the Debian DFSG and is
    # not included in official releases.  For more information, see
    # <https://www.debian.org/social_contract> and also
    # <http://wiki.debian.org/Firmware>.
    #
    # WARNING: Wireless connections are *NOT* recommended for backup
    # and restore operations, but are included for other uses.
    #
    cat >> $ROOT/$FILE <<EOL
echo "Adding non-free packages..."
# Briefly activate non-free repo to install non-free firmware packages
perl -p -i -e 's/main$/main non-free/' /etc/apt/sources.list
apt update --yes
apt install --yes --no-install-recommends \
    firmware-linux-nonfree \
    firmware-atheros \
    firmware-brcm80211 \
    firmware-iwlwifi
update-initramfs -u
perl -p -i -e 's/ non-free$//' /etc/apt/sources.list
apt update --yes
EOL
}

script_shell() {
    #
    # Setup script: Insert command to open shell for making changes
    #
    cat >> $ROOT/$FILE << EOL
echo -e "$red>>> Opening interactive shell. Type 'exit' when done making changes.$off"
echo
bash
EOL
}

script_config() {
    #
    # Setup script: Configure the system
    #
    cat >> $ROOT/$FILE <<EOL
# Autologin for shell
mkdir -p /etc/systemd/system/getty@tty1.service.d
cat > /etc/systemd/system/getty@tty1.service.d/override.conf <<END
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin $USER --noclear %I 38400 linux
END

# Autologin for lightdm
[ -f /etc/lightdm/lightdm.conf ] && sed -i "s/.*autologin-user=.*/autologin-user=$USER/" /etc/lightdm/lightdm.conf

# No password for sudo
sed -i "s/.*sudo.*ALL=(ALL:ALL) ALL/%sudo ALL=(ALL) NOPASSWD:ALL/" /etc/sudoers

# Update kernel module of depends
uname_r=\$(dpkg-query -W -f='\${binary:Package}\n' linux-image-* | head -n 1 | sed 's/linux-image-//')
depmod -b / \$uname_r

# Add extra modules to initrd
[ -z \$(grep ^md /etc/initramfs-tools/modules) ] && echo md >> /etc/initramfs-tools/modules

# Update initrd
update-initramfs -u
lsinitramfs /boot/initrd*
EOL
}

script_exit() {
    #
    # Setup script: Clean up and exit
    #
    cat >> $ROOT/$FILE <<EOL
# Save space
rm -f /usr/bin/{localedef,perl5.*,python3*m}
rm -f /usr/share/icons/*/icon-theme.cache
rm -rf /usr/share/doc
rm -rf /usr/share/man

# Clean up and exit
apt autopurge --yes && apt clean
[ -L /bin/X11 ] && unlink /bin/X11
[ -d $ROOT/usr/share/locale/zh_CN ] && ls -d $ROOT/usr/share/locale/* | grep -v -w en | grep -v -w en_US | xargs rm -rf
rm -rf /var/lib/dbus/machine-id
rm -rf /tmp/*
rm -f /etc/resolv.conf
rm -rf /var/lib/apt/lists/????????*
exit
EOL
}

chroot_exec() {
    #
    # Execute setup script inside chroot environment
    #
    echo -e "$yel* Copying assets to root directory...$off"

    # Copy /etc/resolv.conf before running setup script
    cp /etc/resolv.conf $ROOT/etc/

    # Run setup script inside chroot
    chmod +x $ROOT/$FILE
    echo
    echo -e "$red>>> ENTERING CHROOT SYSTEM$off"
    echo
    sleep 2
    chroot_mount
    chroot $ROOT/ /bin/bash -c "./$FILE"
    chroot_umount
    echo
    echo -e "$red>>> EXITED CHROOT SYSTEM$off"
    echo
    sleep 2
    rm -f $ROOT/$FILE
}

create_livefs() {
    #
    # Prepare to create new image
    #
    echo -e "$yel* Preparing image...$off"
    chroot_umount
    rm -f $ROOT/root/.bash_history
    rm -rf image mini-rescue-$VER.iso
    mkdir -p image/live

    # Compress live filesystem
    echo -e "$yel* Compressing live filesystem...$off"
    mksquashfs $ROOT image/live/filesystem.squashfs -comp zstd -e boot
}

create_iso() {
    #
    # Create ISO image from existing live filesystem
    #
    chroot_umount
    if [ ! -s "image/live/filesystem.squashfs" ]; then
        echo -e "$red* ERROR: The squashfs live filesystem is missing.$off\n"
        exit
    fi

    # Sync boot stuff
    rsync -avh efi/ image/

    # Update version number
    perl -p -i -e "s/\\\$VERSION/$VER/g" image/boot/grub/grub.cfg

    # Update base distro
    perl -p -i -e "s/\\\$BASE/$BASE/g" image/boot/grub/grub.cfg

    # Prepare boot image
    cache_dir=cache
    if [ ! -f "$cache_dir/usr/bin/grub-mkstandalone" ]; then
        rm -rf $cache_dir
        mkdir -p $cache_dir
        tar -xpvf debootstrap-$BASE-$ARCH.tar.zst --directory=$cache_dir
        pushd $cache_dir
            mv $ROOT/* .
            rm -r $ROOT
        popd
    fi

    cp -f image/boot/grub/grub.cfg $cache_dir/
    root_bak=$ROOT
    export ROOT=$cache_dir
    cat >> $ROOT/$FILE <<EOL
    export DEBIAN_FRONTEND=noninteractive
    apt install --yes --no-install-recommends \
        grub-efi-amd64-bin grub-efi-amd64-signed shim-signed grub-pc-bin fonts-hack
    # Generate GRUB font
    grub-mkfont -n Cantarell -o yuchen.pf2 -s16 -v /usr/share/fonts/truetype/hack/Hack-Regular.ttf
    # Create image for BIOS and CD-ROM
    grub-mkstandalone \
        --format=i386-pc \
        --output=core.img \
        --install-modules="linux normal iso9660 biosdisk memdisk search help tar ls all_video font gfxmenu png" \
        --modules="linux normal iso9660 biosdisk search help all_video font gfxmenu png" \
        --locales="" \
        --fonts="yuchen" \
        "boot/grub/grub.cfg=grub.cfg"
    # Prepare image for UEFI
    cat /usr/lib/grub/i386-pc/cdboot.img core.img > bios.img
EOL
    script_exit
    chroot_exec
    export ROOT=$root_bak

    mkdir -p {image/{EFI/boot,boot/grub/fonts},scratch}
    touch image/DENG
    cp -f $cache_dir/bios.img scratch/
    cp -rf $cache_dir/usr/lib/grub/x86_64-efi image/boot/grub/
    cp -f $cache_dir/usr/lib/shim/shimx64.efi.signed image/EFI/boot/bootx64.efi
    cp -f $cache_dir/usr/lib/grub/x86_64-efi-signed/grubx64.efi.signed image/EFI/boot/grubx64.efi
    cp -f $cache_dir/yuchen.pf2 image/boot/grub/fonts/
    cp -f $ROOT/boot/vmlinuz-* image/vmlinuz
    cp -f $ROOT/boot/initrd.img-* image/initrd.img

    # Create EFI partition
    UFAT="scratch/efiboot.img"
    dd if=/dev/zero of=$UFAT bs=1M count=3
    mkfs.vfat $UFAT
    mcopy -s -i $UFAT image/EFI ::

    # Create final ISO image
    iso_image_file=mini-rescue-$BASE$1-$VER.iso
    xorriso \
        -as mkisofs \
        -r -o $iso_image_file \
        -iso-level 3 \
        -full-iso9660-filenames \
        -J -joliet-long \
        -volid "Mini Rescue $VER" \
        -eltorito-boot \
            boot/grub/bios.img \
            -no-emul-boot \
            -boot-load-size 4 \
            -boot-info-table \
            --eltorito-catalog boot/grub/boot.cat \
        --grub2-boot-info \
        --grub2-mbr $cache_dir/usr/lib/grub/i386-pc/boot_hybrid.img \
        -eltorito-alt-boot \
            -e EFI/efiboot.img \
            -no-emul-boot \
        -append_partition 2 0xef scratch/efiboot.img \
        -graft-points \
            image \
            /boot/grub/bios.img=scratch/bios.img \
            /EFI/efiboot.img=scratch/efiboot.img

    # Report final ISO size
    echo -e "$yel\nISO image saved:"
    du -sh $iso_image_file
    echo -e "$off"
    echo
    echo "Done."
    echo
}


#
# Execute functions based on the requested action
#

if [ "$ACTION" == "clean" ]; then
    # Clean all build files
    clean
fi

if [ "$ACTION" == "" ]; then
    # Build new ISO image
    prepare
    script_init
    script_base
    script_desktop
    if [ "$NONFREE" = true ]; then
        echo -e "$yel* Including non-free packages...$off"
        script_add_nonfree
    else
        echo -e "$yel* Excluding non-free packages.$off"
    fi
    script_config
    script_exit
    chroot_exec
    create_livefs
    create_iso
fi

if [ "$ACTION" == "base" ]; then
    # Create base system
    prepare
    script_init
    script_base
    script_config
    script_exit
    chroot_exec
    create_livefs
    create_iso "-base"
fi

if [ "$ACTION" == "changes" ]; then
    # Enter existing system to make changes
    echo -e "$yel* Updating existing image.$off"
    script_init
    script_shell
    script_config
    script_exit
    chroot_exec
    create_livefs
    create_iso
fi

if [ "$ACTION" == "boot" ]; then
    # Rebuild existing ISO image (update bootloader)
    create_iso
fi
