# archlinux-image-builder

This is a script that builds .img- and .qcow2-files containing a complete Arch Linux system. Both files are <=1GB in size. They can be run in a virtual machine, or written directly into any drive. The image uses a UKI (Unified Kernel Image) to boot, which requires UEFI. A compatible machine can be created with the following command, assuming you have virt-manager installed.

```
sudo virsh define vm.xml
```