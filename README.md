# archlinux-image-builder

This is a script that builds .img- and .qcow2-files containing a complete Arch Linux system. Both files are <=1GB in size. They can be run in a virtual machine, or written directly into any drive. The image uses a UKI (Unified Kernel Image) to boot, which requires UEFI. A compatible machine can be created with the following command, assuming you have virt-manager installed.

How to get a quick virtual machine:

```bash
./build.sh "$(cat cmd.sh)" # build the image, add commands to open an ssh server
rm archfile.img # not needed for a vm
cp archfile.qcow2 archfile.qcow2b # backup the image
sudo virsh define vm.xml # create the vm
sudo virsh start archlinux-3 # start the vm
# quick alias to ssh in
alias sshvirt='ssh root@$(sudo virsh net-dhcp-leases default | grep -Po "(\d{1,3}\.){3}\d{1,3}")'
sshvirt # do your stuff

# resetting the vm:
sudo virsh shutdown archlinux-3; sleep 1
cp archfile.qcow2b archfile.qcow2
sudo virsh start archlinux-3
```