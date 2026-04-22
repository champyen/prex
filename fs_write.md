### Goal
Currently fs or fatfs has file writing issue
However, when try to write data, system will cause Data Abort

### configure
 * Prex fs server implement:
  ./usr/server/fs/
 * Prex FATFS impleemnt:
  ./usr/server/fs/fatfs/

### mount disk
* modify conf/etc/fstab, add a line as below:
/dev/vd0        /mnt/vd0        fatfs

### write file
* modify conf/etc/rc
$ cp /mnt/vd0/LICENSE /mnt/vd0/LICENSE.TXT

### Build
1. configure the target (refer ./doc/integrator.md )
$ ./configure --target=arm-qemu-virt --cross-prefix=arm-none-eabi --enable-mmu

2. build & clean
  - to build
  $ make -j4
  - to clean
  $ make clean
3. run with QEMU (remember to use timeout to control, don't add "-serial stdio" that's for old version qemu):
QEMU command to run Prex on QEMU virt platform and get boot logz:
$ timeout 15 \
  qemu-system-arm -M virt -m 256M -kernel prexos.bin -nographic \
  -drive if=none,file=disk.img,id=drv0,format=raw -device virtio-blk-device,drive=drv0 \
  > qemu.log 2>&1 & sleep 16 && cat qemu.log

### disk image build
You don't need to request sudo from me, the following tools can be used without sudo
1. image creation: you can make use of qemu-img
2. partition, format: add /usr/sbin to PATH, you can use fdisk and "mkfs.vfat -s 64" to format
3. image manipulation: mtools is installed, please use it to copy concret files into image
4. checking: you can make use of fusefatfs to mount and view directly, remember to umount with fusermount

### Output
Prex can write file to disk image. for example

Don't stop before fix the panic
