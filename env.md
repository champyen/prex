# Current Support Targets
* arm-gba (no MMU support)
* arm-raspi0
* arm-qemu-virt
* x86-pc

# Build
1. configure the target (refer ./doc/integrator.md )
  * ARM targets
  $ ./configure --target=$TARGET --cross-prefix=arm-none-eabi [--enable-mmu]
  * x86 targets
  $ ./configure --target=$TARGET [--enable-mmu]

2. build & clean
* to build
$ make -j4
* to clean
$ make clean


# QEMU launch command example to get console log
## WARNINGS
1. Don't take away "sleep" command, without it you can't get redirected console log
2. Attach all specified devices for each platform

## COMMANDS
QEMU command to run Prex+ on QEMU virt platform and get boot logz:
* arm-raspi0
$ timeout 15 \
  qemu-system-arm -M raspi0 -kernel prexos_full.bin -nographic -sd disk.img \
  > qemu.log 2>&1 & sleep 16 && cat qemu.log

* arm-integrator
$ timeout 15 \
  qemu-system-arm -M integratorcp -kernel prexos_full.bin -nographic \
  > qemu.log 2>&1 & sleep 16 && cat qemu.log

* arm-qemu-virt
$ timeout 15 \
  qemu-system-arm -M virt -m 256M -kernel prexos.bin -nographic \
  -drive if=none,file=disk.img,id=drv0,format=raw -device virtio-blk-device,drive=drv0 \
  -drive if=none,file=bin.img,id=drv1,format=raw -device virtio-blk-device,drive=drv1 \
  -device virtio-sound-device,audiodev=audio0 -audiodev pa,id=audio0 \
  -netdev user,id=net0 -device virtio-net-device,netdev=net0 \
  > qemu.log 2>&1 & sleep 16 && cat qemu.log

# tiered volumes (ARFS/FATFS)
Prex+ supports multiple volumes:
1. prexos.bin: Core boot volume (ARFS), contains kernel and basic servers.
2. bin.img: Secondary volume (ARFS), usually mounted at /bin. 
   Attached as drv1 (vd1) in QEMU for arm-qemu-virt.
3. disk.img: Tertiary volume (FATFS), usually mounted at /usr.
   Attached as drv0 (vd0) in QEMU for arm-qemu-virt.

# disk image build
You don't need to request sudo from me, the following tools to manipulate disk image can be used without sudo
1. image creation: you can make use of qemu-img
2. partition, format: add /usr/sbin to PATH, you can use mkfs.vfat format disk image directly
3. image manipulation: mtools is installed, please use it to copy concret files into image
4. checking: you can make use of fusefatfs to mount and view directly, remember to umount with fusermount
