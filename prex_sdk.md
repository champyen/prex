## Goal
Prepare Prex SDK

## SDK files build up
create a ./sdk directory, which provides the required files to build application outside prexos.bin folder:
* linker scripts (copy both, name a good folder to keep)
  - user.ld
  - user-nommu.ld
* lib/
  - crt*.o
  - .a static libraries (libc.a)
* include/
  - usr/include/
  - include/ipc
  - include/machine
* Makefile & .mk files
  - e.g.: config.mk
  - to setup a standalone build environment
* examples
  - hello
  - helixmp3
  - tetris

## Develop
### STAGE 1
In this stage we are explore the files required to build sdk
* use the toolchain specified in conf/config.mk
* create sdk/config.mk (can be placed in usr/sdk/ to be commited)
  - provide a config flag to switch between mmu and nommu
* verify to build program and put into disk image bin/ directory

### STAGE 2
In this stage, create build rules to generate SDK
* add option sdk in conf/arm/qemu-virt.base
* use CONFIG_SDK in config.mk to trigger the flow to copy sdk files into ./sdk directory
* verify the content by building test put into disk image bin/ directory

### STAGE 3
Now we challege to use ../tinycc/ as compiler
* build arm-none-eabi crosstool chain (refer to ../tinycc/tinycc_arm-none-eabi.md)
* modify config.mk to use tinycc as compiler and linker
* verify the content by building test put into disk image bin/ directory

### Build
1. configure the target (refer ./doc/integrator.md )
$ ./configure --target=arm-qemu-virt --cross-prefix=arm-none-eabi --enable-mmu

2. build & clean
  - to build
  $ make -j4
  - to clean
  $ make clean

3. mount point
  * modify conf/etc/fstab
    - mount /dev/vd0p1 to /usr/

### QEMU launch command example to get console log
QEMU command to run Prex on QEMU virt platform and get boot logz:
$ timeout 15 \
  qemu-system-arm -M virt -m 256M -kernel prexos.bin -nographic \
  -drive if=none,file=disk.img,id=drv0,format=raw -device virtio-blk-device,drive=drv0 \
  -device virtio-sound-device,audiodev=audio0 -audiodev pa,id=audio0 \
  > qemu.log 2>&1 & sleep 16 && cat qemu.log

### disk image build
You don't need to request sudo from me, the following tools can be used without sudo
1. image creation: you can make use of qemu-img
2. partition, format: add /usr/sbin to PATH, you can use "fdisk/sfdisk" to partition and "mkfs.vfat" to format
3. image manipulation: mtools is installed, please use it to copy concret files into image
4. checking: you can make use of fusefatfs to mount and view directly, remember to umount with fusermount

## Output
./sdk can be generated via sdk option in conf/*/*.base
And the sdk can be used to build applications standalone
