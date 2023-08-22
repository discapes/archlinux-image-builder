#!/bin/bash

set -euo pipefail

sudo pacman -S --needed --noconfirm arch-install-scripts
imgfile=/dev/shm/archfile.img

rm -rf $imgfile && touch $imgfile
dd if=/dev/zero of=$imgfile bs=1G count=2
echo "o-y n-1--+300M-ef00 n-2---8300 p w-y" | sed 's/[ -]/\n/g' | gdisk $imgfile >/dev/null
fdisk -l $imgfile

sudo \
efistart=$(fdisk -l $imgfile | tail -2 | head -1 | tr -s ' ' | cut -d' ' -f2) \
efisize=$(fdisk -l $imgfile | tail -2 | head -1 | tr -s ' ' | cut -d' ' -f4) \
sysstart=$(fdisk -l $imgfile | tail -1 | tr -s ' ' | cut -d' ' -f2) \
syssize=$(fdisk -l $imgfile | tail -1 | tr -s ' ' | cut -d' ' -f4) \
bs=$(fdisk -l $imgfile | head -2 | tail -1 | rev | cut -f2 -d' ' | rev) \
imgfile=$imgfile \
bash <<'EOF'
if mountpoint -q /mnt ; then
	fuser -km /mnt
	sleep 1
	umount -R /mnt
fi
while [[ "$(losetup -l --noheadings --raw)" =~ loop[01] ]]; do losetup -D; echo waiting for loop devices to detach; sleep 1; done
losetup -o $((efistart*bs)) --sizelimit $((efisize*bs)) /dev/loop0 $imgfile
losetup -o $((sysstart*bs)) --sizelimit $((syssize*bs)) /dev/loop1 $imgfile
mkfs.fat -F32 /dev/loop0
mkfs.ext4 /dev/loop1
mount /dev/loop1 /mnt
mkdir /mnt/boot
mount /dev/loop0 /mnt/boot
pacstrap -K /mnt base neovim cloud-guest-utils
# piping would cause input to be left unread, causing pipefail
head -n 6 < <(genfstab -U /mnt) > /mnt/etc/fstab
EOF

sudo arch-chroot /mnt bash <<'EOF'
set -euo pipefail
ln -sf /usr/share/zoneinfo/Europe/Helsinki /etc/localtime
hwclock --systohc
echo -e "en_US.UTF-8 UTF-8\nfi_FI.UTF-8 UTF-8" > /etc/locale.gen
locale-gen
echo LANG=en_US.UTF-8 > /etc/locale.conf
echo KEYMAP=fi > /etc/vconsole.conf
echo archfile > /etc/hostname
echo -e "toor\ntoor" | passwd
ln -s nvim /usr/bin/vim
ln -s nvim /usr/bin/vi

# NETWORK
cat <<EOF2> /etc/systemd/network/20-wired.network
[Match]
Type=ether
[Network]
DHCP=yes
DNS=1.1.1.1
EOF2
systemctl enable systemd-networkd systemd-resolved

# GROWPART
cat <<EOF2> /etc/systemd/system/firstboot.service
[Unit]
Description=Initialize system once
[Service]
Type=simple
ExecStart=/firstboot.sh
[Install]
WantedBy=multi-user.target 
EOF2

cat <<EOF2> /firstboot.sh
#!/bin/sh
growpart /dev/sda 2
resize2fs /dev/sda2
systemctl disable firstboot.service 
rm -f /etc/systemd/system/firstboot.service
rm -f /firstboot.sh
EOF2

systemctl enable firstboot.service
chmod +x /firstboot.sh

# BOOT
mkdir -p /boot/efi/boot /etc/mkinitcpio.d
echo root=/dev/sda2 rw > /etc/kernel/cmdline
cat <<EOF2> /etc/mkinitcpio.d/linux.preset 
ALL_kver="/boot/vmlinuz-linux"
PRESETS=('default')
default_uki="/boot/efi/boot/bootx64.efi"
EOF2
pacman -S --noconfirm linux
pacman -Scc --noconfirm
EOF

sudo fuser -km /mnt
sleep 1
sudo umount -R /mnt
while [[ "$(losetup -l --noheadings --raw)" =~ loop[01] ]]; do sudo losetup -D; echo waiting for loop devices to detach; sleep 1; done
qemu-img convert -f raw -O qcow2 $imgfile archfile.qcow2
rm $imgfile
qemu-img resize archfile.qcow2 20G
