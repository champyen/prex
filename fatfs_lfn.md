### Goal
Current Prex Fat32 implementation doesn't support long file name (LFN).
* Fatfs implementation
usr/server/fs/fatfs

### Fatfs source code
Please refer to the FatFs library to implement long file name.
../Fatfs_r16/

### Build
1. configure the target (refer ./doc/integrator.md )
$ ./configure --target=arm-qemu-virt --cross-prefix=arm-none-eabi --enable-mmu

2. build & clean
  - to build
  $ make -j4
  - to clean
  $ make clean

### mount table & init script
* mount table for booting
conf/etc/fstab
* init script
conf/etc/rc
* must make to build image

### QEMU launch command example to get console log
QEMU command to run Prex on QEMU virt platform and get boot logz:
$ timeout 15 \
  qemu-system-arm -M virt -m 256M -kernel prexos.bin -nographic \
  -drive if=none,file=fat32.img,id=drv0,format=raw -device virtio-blk-device,drive=drv0 \
  -device virtio-sound-device,audiodev=audio0 -audiodev pa,id=audio0 \
  > qemu.log 2>&1 & sleep 16 && cat qemu.log

### disk image build
You don't need to request sudo from me, the following tools can be used without sudo
1. image creation: you can make use of qemu-img
2. partition, format: add /usr/sbin to PATH, you can use fdisk and "mkfs.vfat -s 64" to format
3. image manipulation: mtools is installed, please use it to copy concret files into image
4. checking: you can make use of fusefatfs to mount and view directly, remember to umount with fusermount

### Output
* ls the mount point, Prex+ can list files with long filename
* cp file with long file name can work correctly
