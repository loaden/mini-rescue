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

VER=0.1
BASE=buster
ARCH=amd64
ROOT=rootdir
FILE=setup.sh
USER=live
NONFREE=true
MIRROR=https://mirrors.tuna.tsinghua.edu.cn/debian

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

clean() {
	#
	# Remove all build files
	#
	rm -rf {image,scratch,$ROOT,*.iso}
	echo -e "$yel* All clean!$off\n"
	exit
}

prepare() {
	#
	# Prepare host environment
	#
	echo -e "$yel* Building from scratch.$off"
	rm -rf {image,scratch,$ROOT,*.iso}
	CACHE=debootstrap-$BASE-$ARCH.tar.zst
	if [ -f "$CACHE" ]; then
		echo -e "$yel* $CACHE exists, extracting existing archive...$off"
		sleep 2
		tar -xpvf $CACHE
	else
		echo -e "$yel* $CACHE does not exist, running debootstrap...$off"
		sleep 2
		apt install --yes --no-install-recommends debootstrap squashfs-tools zstd \
			grub-efi-amd64-signed shim-signed mtools xorriso
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

# System mounts
mount none -t proc /proc
mount none -t sysfs /sys
mount none -t devpts /dev/pts

# Set hostname
echo 'mrescue' > /etc/hostname

# Set hosts
cat > /etc/hosts <<END
127.0.0.1  localhost
127.0.1.1  mrescue
::1        localhost ip6-localhost ip6-loopback
ff02::1    ip6-allnodes
ff02::2    ip6-allrouters
END

# Set default locale
cat >> /etc/bash.bashrc <<END
export LANG="C"
export LC_ALL="C"
END

# Export environment
export HOME=/root; export LANG=C; export LC_ALL=C;
EOL
}

script_build() {
	#
	# Setup script: Install packages
	#
	if [[ "$ARCH" == "i386" || "$ARCH" == "x86" ]]; then
		KERN="686"
	else
		KERN="amd64"
	fi
	cat >> $ROOT/$FILE <<EOL
# Install packages
export DEBIAN_FRONTEND=noninteractive
apt install --yes --no-install-recommends \
	\
	linux-image-$KERN live-boot systemd-sysv firmware-linux-free sudo rsync \
    nano pm-utils iputils-ping net-tools \
	\
	xserver-xorg x11-xserver-utils xinit openbox obconf slim compton dbus-x11 xvkbd \
	gir1.2-notify-0.7 nitrogen gsettings-desktop-schemas network-manager-gnome \
	xfce4-terminal libcanberra-gtk3-module xfce4-appfinder xfce4-power-manager libexo-1-0 \
	thunar thunar-archive-plugin xarchiver zstd catfish mousepad gpicview \
	\
	beep laptop-detect os-prober discover lshw-gtk hdparm smartmontools \
	time lvm2 gparted gnome-disk-utility gddrescue testdisk \
	dosfstools ntfs-3g reiserfsprogs reiser4progs hfsutils jfsutils \
	f2fs-tools exfat-fuse exfat-utils btrfs-progs \
	\
	$EXTRA_PACKAGES

# Add regular user
useradd --create-home $USER --shell /bin/bash
adduser $USER sudo
echo '$USER:$USER' | chpasswd

# Prepare single-user system
echo 'root:$USER' | chpasswd
echo 'default_user root' >> /etc/slim.conf
echo 'auto_login yes' >> /etc/slim.conf

# Fake nautilus
ln -s /usr/bin/thunar /usr/bin/nautilus
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
#
# To include firmware, uncomment or add packages as needed here in the
# make script to create a custom image.
#
apt install --yes \
	firmware-linux-nonfree
#	firmware-atheros \
#	firmware-brcm80211 \
#	firmware-iwlwifi \
#	firmware-libertas \
#	firmware-zd1211 \
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
rm -rf /var/lib/dbus/machine-id
rm -rf /tmp/*
rm -f /etc/resolv.conf
rm -rf /var/lib/apt/lists/????????*
umount -lf /proc
umount /sys
umount /dev/pts
exit
EOL
}

chroot_exec() {
	#
	# Execute setup script inside chroot environment
	#
	echo -e "$yel* Copying assets to root directory...$off"

	# Copy /etc/resolv.conf before running setup script
	cp /etc/resolv.conf ./$ROOT/etc/

	# Run setup script inside chroot
	chmod +x $ROOT/$FILE
	echo
	echo -e "$red>>> ENTERING CHROOT SYSTEM$off"
	echo
	sleep 2
	chroot $ROOT/ /bin/bash -c "./$FILE"
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
	rm -f $ROOT/root/.bash_history
	rm -rf image mrescue-$VER.iso
	mkdir -p image/live

	# Fix permissions
	chroot $ROOT/ /bin/bash -c "chown -R root: /etc /root"

	# Compress live filesystem
	echo -e "$yel* Compressing live filesystem...$off"
	mksquashfs $ROOT/ image/live/filesystem.squashfs -comp zstd -e boot
}

create_iso() {
	#
	# Create ISO image from existing live filesystem
	#
	if [ "$BASE" == "stretch" ]; then
		# Debian 9 supports legacy BIOS booting
		create_legacy_iso
	else
		# Debian 10+ supports UEFI and secure boot
		create_uefi_iso
	fi
}

create_legacy_iso() {
	#
	# Create legacy ISO image for Debian 9 (version 2.0 releases)
	#
	if [ ! -s "image/live/filesystem.squashfs" ]; then
		echo -e "$red* ERROR: The squashfs live filesystem is missing.$off\n"
		exit
	fi

	# Apply image changes from overlay
	echo -e "$yel* Applying image changes from overlay...$off"
	rsync -h --info=progress2 --archive \
		./overlay/image/* \
		./image/

	# Remove EFI-related boot assets
	rm -rf image/boot

	# Update version number
	perl -p -i -e "s/\\\$VERSION/$VER/g" image/isolinux/isolinux.cfg

	# Prepare image
	echo -e "$yel* Preparing legacy image...$off"
	mkdir image/isolinux
	cp $ROOT/boot/vmlinuz* image/live/vmlinuz
	cp $ROOT/boot/initrd* image/live/initrd
	cp /boot/memtest86+.bin image/live/memtest
	cp /usr/lib/ISOLINUX/isolinux.bin image/isolinux/
	cp /usr/lib/syslinux/modules/bios/menu.c32 image/isolinux/
	cp /usr/lib/syslinux/modules/bios/vesamenu.c32 image/isolinux/
	cp /usr/lib/syslinux/modules/bios/hdt.c32 image/isolinux/
	cp /usr/lib/syslinux/modules/bios/ldlinux.c32 image/isolinux/
	cp /usr/lib/syslinux/modules/bios/libutil.c32 image/isolinux/
	cp /usr/lib/syslinux/modules/bios/libmenu.c32 image/isolinux/
	cp /usr/lib/syslinux/modules/bios/libcom32.c32 image/isolinux/
	cp /usr/lib/syslinux/modules/bios/libgpl.c32 image/isolinux/
	cp /usr/share/misc/pci.ids image/isolinux/

	# Create ISO image
	echo -e "$yel* Creating legacy ISO image...$off"
	xorriso -as mkisofs -r \
		-J -joliet-long \
		-isohybrid-mbr /usr/lib/ISOLINUX/isohdpfx.bin \
		-partition_offset 16 \
		-A "Redo $VER" -volid "Redo Rescue $VER" \
		-b isolinux/isolinux.bin \
		-c isolinux/boot.cat \
		-no-emul-boot -boot-load-size 4 -boot-info-table \
		-o mrescue-$VER.iso \
		image

	# Report final ISO size
	echo -e "$yel\nISO image saved:"
	du -sh mrescue-$VER.iso
	echo -e "$off"
	echo
	echo "Done."
	echo
}

create_uefi_iso() {
	#
	# Create ISO image for Debian 10 (version 3.0 releases)
	#
	if [ ! -s "image/live/filesystem.squashfs" ]; then
		echo -e "$red* ERROR: The squashfs live filesystem is missing.$off\n"
		exit
	fi

	# Apply image changes from overlay
	echo -e "$yel* Applying image changes from overlay...$off"
	rsync -h --info=progress2 --archive \
		./overlay/image/* \
		./image/

	# Remove legacy boot assets
	rm -rf image/isolinux

	# Update version number
	perl -p -i -e "s/\\\$VERSION/$VER/g" image/boot/grub/grub.cfg

	# Prepare boot image
	touch image/REDO
        cp $ROOT/boot/vmlinuz* image/vmlinuz
        cp $ROOT/boot/initrd* image/initrd
	mkdir -p {image/EFI/{boot,debian},image/boot/grub/{fonts,theme},scratch}
	cp /usr/share/grub/ascii.pf2 image/boot/grub/fonts/
	cp /usr/lib/shim/shimx64.efi.signed image/EFI/boot/bootx64.efi
	cp /usr/lib/grub/x86_64-efi-signed/grubx64.efi.signed image/EFI/boot/grubx64.efi
	cp -r /usr/lib/grub/x86_64-efi image/boot/grub/

	# Create EFI partition
	UFAT="scratch/efiboot.img"
	dd if=/dev/zero of=$UFAT bs=1M count=4
	mkfs.vfat $UFAT
	mcopy -s -i $UFAT image/EFI ::

	# Create image for BIOS and CD-ROM
	grub-mkstandalone \
		--format=i386-pc \
		--output=scratch/core.img \
		--install-modules="linux normal iso9660 biosdisk memdisk search help tar ls all_video font gfxmenu png" \
		--modules="linux normal iso9660 biosdisk search help all_video font gfxmenu png" \
		--locales="" \
		--fonts="" \
		"boot/grub/grub.cfg=image/boot/grub/grub.cfg"

	# Prepare image for UEFI
	cat /usr/lib/grub/i386-pc/cdboot.img scratch/core.img > scratch/bios.img

	# Create final ISO image
	xorriso \
		-as mkisofs \
		-iso-level 3 \
		-full-iso9660-filenames \
		-joliet-long \
		-volid "Redo Rescue $VER" \
		-eltorito-boot \
			boot/grub/bios.img \
			-no-emul-boot \
			-boot-load-size 4 \
			-boot-info-table \
			--eltorito-catalog boot/grub/boot.cat \
		--grub2-boot-info \
		--grub2-mbr /usr/lib/grub/i386-pc/boot_hybrid.img \
		-eltorito-alt-boot \
			-e EFI/efiboot.img \
			-no-emul-boot \
		-append_partition 2 0xef scratch/efiboot.img \
		-output mrescue-$VER.iso \
		-graft-points \
			image \
			/boot/grub/bios.img=scratch/bios.img \
			/EFI/efiboot.img=scratch/efiboot.img

	# Remove scratch directory
	rm -rf scratch

	# Report final ISO size
	echo -e "$yel\nISO image saved:"
	du -sh mrescue-$VER.iso
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
	create_livefs
	exit
	# Build new ISO image
	prepare
	script_init
	script_build
	if [ "$NONFREE" = true ]; then
		echo -e "$yel* Including non-free packages...$off"
		script_add_nonfree
	else
		echo -e "$yel* Excluding non-free packages.$off"
	fi
	script_exit
	chroot_exec
#	create_livefs
#	create_iso
fi

if [ "$ACTION" == "changes" ]; then
	# Enter existing system to make changes
	echo -e "$yel* Updating existing image.$off"
	script_init
	script_shell
	script_exit
	chroot_exec
	create_livefs
	create_iso
fi

if [ "$ACTION" == "boot" ]; then
	# Rebuild existing ISO image (update bootloader)
	create_iso
fi
