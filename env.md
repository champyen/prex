### Build
1. configure the target (refer ./doc/integrator.md )
$ ./configure --target=arm-qemu-virt --cross-prefix=arm-none-eabi --enable-mmu

2. build & clean
* to build
$ make -j4
* to clean
$ make clean


### QEMU launch command example to get console log
QEMU command to run Prex on QEMU virt platform and get boot logz:
$ timeout 15 \
  qemu-system-arm -M virt -m 256M -kernel prexos -nographic \
  -drive if=none,file=disk.img,id=drv0,format=raw -device virtio-blk-device,drive=drv0 \
  -device virtio-sound-device,audiodev=audio0 -audiodev pa,id=audio0 \
  -netdev user,id=net0 -device virtio-net-device,netdev=net0 \
  > qemu.log 2>&1 & sleep 16 && cat qemu.log

### disk image build
You don't need to request sudo from me, the following tools can be used without sudo
1. image creation: you can make use of qemu-img
2. partition, format: add /usr/sbin to PATH, you can use mkfs.vfat format disk image directly
3. image manipulation: mtools is installed, please use it to copy concret files into image
4. checking: you can make use of fusefatfs to mount and view directly, remember to umount with fusermount
