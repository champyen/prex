Here are some notes of using QEMU

### Disk images
1. install mtools

2. create partition in the image
$ fdisk sdcard.img

3. mkfs.vaft with offset
$ mkfs.vfat -F32 --offset=2048 sdcard.img

4. use mtools to manipute (1048576 = 2048*512, the offset of partition table)
$ mcopy -i sdcard@1048576 SRC_FILE ::DST_FILE
$ mdir -i sdcard@1048576 ::

### Timeout
'timeout Ns' command provides you the easiest way to run a oneshot test without worries of kill the process
$ timeout 5s qemu-system-arm ...

### Device Trace with "-d trace:dev*" argument
During development of device driver, you should enable the trace feature for the device you are develop driver for
$ qemu-system-arm -M raspi0 -kernel prexos -nographic -d trace:bcm2835_host*
