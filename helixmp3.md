### Goal
port mp3 player based on Helix mp3 library to Prex+ OS as helixmp3
* don't delegate to sub-agent
* remember to add permission in conf/etc/security
* remember to copy license file to target directory

### source
../Helix-MP3-Decoder
* refer to usr/sample/playwav for sndio playback flow
  - don't modify the source of driver and sndio server

### Build
1. configure the target (refer ./doc/integrator.md )
$ ./configure --target=arm-qemu-virt --cross-prefix=arm-none-eabi --enable-mmu

2. build & clean
  - to build
  $ make -j4
  - to clean
  $ make clean


### QEMU launch command example to get console log
QEMU command to run Prex on QEMU virt platform and get boot logz:
$ timeout 15 \
  qemu-system-arm -M virt -m 256M -kernel prexos.bin -nographic \
  -drive if=none,file=disk.img,id=drv0,format=raw -device virtio-blk-device,drive=drv0 \
  -device virtio-sound-device,audiodev=audio0 -audiodev pa,id=audio0 \
  > qemu.log 2>&1 & sleep 16 && cat qemu.log

### Verification
Please also implement a pure decoding mode for verification (as a stanalone
program or built into helixmp3).
* This mode only decode mp3 bitstream to PCM data, and compared with specified
  PCM file.
* The pure decoding mode must be able to compiled as a host program. And use
  the program to generate decoded PCM data from "sample.mp3".
  - Copy the "sample.pcm" file to the disk image by "mcopy -i disk.img sample.pcm ::/".
  - compare decoded data with the "sample.pcm" on device.
* According to previous experience, the table calculated by fdmlibm has
  incorrect values.
  - Use host initialized table for verification. (use a macro to switch)
  - if fdmlibm has issue, please fix it.

### Implementation Strategy
1. implement decoding only flow, and align the decoded results on host and device
2. add sndio playback flow

### Testing
Try to play mp3 files in disk.img with qemu
* sample.mp3 - 128kbps, stereo, 44KHz

### disk image build
You don't need to request sudo from me, the following tools can be used without sudo
1. image creation: you can make use of qemu-img
2. partition, format: add /usr/sbin to PATH, you can use fdisk and "mkfs.vfat -s 64" to format
3. image manipulation: mtools is installed, please use it to copy concret files into image
  - the image data files are kept in ../fatfs_backup
4. checking: you can make use of fusefatfs to mount and view directly, remember to umount with fusermount

### Output
A player should be implemented under ./usr/sample/helixmp3
It can be used to play mp3 files without crash or hang issue.
You have to use qemu to test before claiming finish.
