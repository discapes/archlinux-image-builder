pacman -S --noconfirm openssh
echo -e "PermitRootLogin yes\nPermitEmptyPasswords yes" >> /etc/ssh/sshd_config
passwd -d root
systemctl enable sshd