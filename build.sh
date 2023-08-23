#!/bin/bash

set -euo pipefail

CMDLINE='quiet video=800x600'
FONT='Lat2-Terminus16'
LOCALECONF='LANG=en_US.UTF-8
LC_NUMERIC=fi_FI.UTF-8
LC_TIME=fi_FI.UTF-8
LC_MONETARY=fi_FI.UTF-8
LC_PAPER=fi_FI.UTF-8
LC_MEASUREMENT=fi_FI.UTF-8'
LOCALES='en_US.UTF-8 UTF-8\nfi_FI.UTF-8 UTF-8'
KEYMAP='fi'
PASSWD='toor'
HOSTNAME='archfile'
TIMEZONE='Europe/Helsinki'

sudo pacman -S --needed --noconfirm arch-install-scripts gdisk qemu-img dosfstools
if [ -n "${CI:-}" ]; then
	imgfile=$(mktemp)
else
	imgfile=/dev/shm/archfile.img
fi
rm -rf $imgfile && touch $imgfile
dd if=/dev/zero of=$imgfile bs=1G count=1
echo "o-y n-1--+40M-ef00 n-2---8300 p w-y" | sed 's/[ -]/\n/g' | gdisk $imgfile >/dev/null
fdisk -l $imgfile

efistart=$(fdisk -l $imgfile | tail -2 | head -1 | tr -s ' ' | cut -d' ' -f2)
efisize=$(fdisk -l $imgfile | tail -2 | head -1 | tr -s ' ' | cut -d' ' -f4)
sysstart=$(fdisk -l $imgfile | tail -1 | tr -s ' ' | cut -d' ' -f2)
syssize=$(fdisk -l $imgfile | tail -1 | tr -s ' ' | cut -d' ' -f4)
bs=$(fdisk -l $imgfile | head -2 | tail -1 | rev | cut -f2 -d' ' | rev)
bootloop=$(sudo losetup -o $((efistart*bs)) --sizelimit $((efisize*bs)) --show -f $imgfile)
rootloop=$(sudo losetup -o $((sysstart*bs)) --sizelimit $((syssize*bs)) --show -f $imgfile)
sudo mkfs.fat -F32 $bootloop
sudo mkfs.ext4 $rootloop
bootuuid=$(lsblk -no UUID $bootloop)
rootuuid=$(lsblk -no UUID $rootloop)

sudo bash <<EOF
if mountpoint -q /mnt ; then
	fuser -km /mnt
	sleep 1
	umount -R /mnt
fi
mount $rootloop /mnt
mkdir /mnt/boot
mount $bootloop /mnt/boot
pacstrap -c -K /mnt base mkinitcpio cloud-guest-utils
# piping would cause input to be left unread, causing pipefail
head -n 6 < <(genfstab -U /mnt) > /mnt/etc/fstab
cat <<EOF2> /mnt/etc/fstab
UUID="$rootuuid"	/		ext4	rw,relatime	0 1
UUID="$bootuuid"	/boot	vfat	rw,relatime	0 2
EOF2
EOF

sudo arch-chroot /mnt bash <<EOF
set -euo pipefail
ln -sf /usr/share/zoneinfo/$TIMEZONE /etc/localtime
hwclock --systohc
echo -e "$LOCALES" > /etc/locale.gen
locale-gen
echo -e "$LOCALECONF" > /etc/locale.conf
echo -e "KEYMAP=$KEYMAP\nFONT=$FONT" > /etc/vconsole.conf
echo $HOSTNAME > /etc/hostname
echo -e "$PASSWD\n$PASSWD" | passwd
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

cat <<'EOF2'> /firstboot.sh
#!/bin/bash
growpart /dev/\$(lsblk -no pkname /dev/disk/by-uuid/$rootuuid) 2
resize2fs /dev/disk/by-uuid/$rootuuid
systemctl disable firstboot.service 
rm -f /etc/systemd/system/firstboot.service
rm -f /firstboot.sh
EOF2

systemctl enable firstboot.service
chmod +x /firstboot.sh


# BOOT
mkdir -p /boot/efi/boot
echo 'root=UUID=$rootuuid rw $CMDLINE' > /etc/kernel/cmdline
sed -i -e 's/base udev/systemd/' -e 's/keyboard keymap consolefont //' /etc/mkinitcpio.conf
cat <<EOF2> /etc/mkinitcpio.d/linux.preset 
ALL_kver="/tmp/vmlinuz-linux"
PRESETS=('default')
default_uki="/boot/efi/boot/bootx64.efi"
EOF2
pacman -S --noconfirm --cachedir /tmp linux
EOF

sudo fuser -km /mnt
sleep 1
sudo umount -R /mnt
while [[ "$(losetup -l --noheadings --raw)" =~ ($bootloop|$rootloop) ]]; do sudo losetup -D; echo waiting for loop devices to detach; sleep 1; done
qemu-img convert -f raw -O qcow2 $imgfile archfile.qcow2
qemu-img resize archfile.qcow2 20G
mv $imgfile archfile.img
