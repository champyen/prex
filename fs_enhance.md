### Goal
Current usr/server/fs is based on cluster/block-based read/write.
It takes several system calls to read a 128KB buffer.
This make fs reading/writing slow

### Scatter / Gather Design
Please design scatter writing and gather reading interface from block device, system call to fs
1. add system call for non-continuous blocks read write
  * design the structure for parameters
  * device_scatter_write
  * device_gather_read
  * can use device_read and device_write to implement
  * related files
    - sys/kern/device.c
    - sys/kern/sysent.c
    - sys/include/device.h
    - include/sys/prex.h
    - usr/lib/prex/syscalls/syscall.h
    - usr/lib/prex/syscalls/device_read.S
    - usr/lib/prex/syscalls/device_write.S
    - doc/kapi.md
2. table-cache fatfs
  * cache buffer for FAT table entries
    - configurable cluster table cache size CONFIG_FATFS_CACHE (in KB)
  * lookup cluster indices for device_scatter_write / device_gather_read to accelerate read/write performance
  * use "#ifdef CONFIG_FATFS_CACHE" to switch normal and scatter/gather design

### Build
1. configure the target (refer ./doc/integrator.md )
$ ./configure --target=arm-qemu-virt --cross-prefix=arm-none-eabi --enable-mmu

2. build & clean
  - to build
  $ make -j4
  - to clean
  $ make clean

### disk image build
You don't need to request sudo from me, the following tools can be used without sudo
1. image creation: you can make use of qemu-img
2. partition, format: add /usr/sbin to PATH, you can use fdisk
3. image manipulation: mtools is installed, please use it to copy concret files into image
  - the image data files are kept in ../fatfs_backup
4. checking: you can make use of fusefatfs to mount and view directly, remember to umount with fusermount

### Test
Please measure the file copy time

### QEMU launch command example to get console log
QEMU command to run Prex on QEMU virt platform and get boot logz:
$ timeout 15 \
  qemu-system-arm -M virt -m 256M -kernel prexos.bin -nographic \
  -drive if=none,file=disk.img,id=drv0,format=raw -device virtio-blk-device,drive=drv0 \
  > qemu.log 2>&1 & sleep 16 && cat qemu.log

### Output
Provide the summary of performance improvement
