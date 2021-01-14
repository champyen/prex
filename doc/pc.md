# Prex x86 PC - HOWTO

*Version 1.3, 2005/09/05*

### Table of Contents

**HOWTO**

- Quick Hacking Guide
- How to create a Prex demo floppy?
- How to run Prex with Bochs?
- How to run Prex with Qemu?
- How to modify the OS boot image?
- How to install the boot sector?

**Technical Note**

- Keyboard Interface
- Debugging with Bochs



## Quick Hacking Guide

There are following three important points to create a Prex boot floppy  for x86-pc.

1. Format the floppy disk with FAT file system.
2. Write the Prex boot sector (bootsect.bin) to the 1st sector.
3. Copy the Prex kernel image (prexos) to the root directory   of the floppy.

Here, the difficult step is 2. To write the boot sector, some special  tool will be needed. Currently, only DOS utility (mkboot.com) is  available in the Prex distribution.

So, I recommend you to create the bootable demo floppy at first. Then,  you can replace the kernel image to your own kernel in the demo floppy.

The following is the most easy step to hack the Prex kernel on x86-pc.

1. Build your own kernel. Please refer to  ["Prex Build Guide"](build.md).  

2. Create the demo floppy. Please refer to  **"How to create a Prex demo floppy?"**

3. Replace the kernel image (prexos) in the demo floppy by your own   image. You can use mtools to do it.  

   ```
    $ mcopy prexos a:\
   ```

     Or, it may be easy to copy it by mounting the FAT file system to the floppy  if your OS supports it.   

4. Boot PC with a created floppy disk.  If the system does not boot with the floppy,  you should check the BIOS settings for the boot device order.  

## How to create a Prex demo floppy?

1. Download the binary file(*.img.gz) for the latest Prex boot floppy from the following web page.
    [  http://prex.sourceforge.net/downloads.htm](http://prex.sourceforge.net/downloads.html) 

2. Unpack the image 

   ```
   $ gunzip prex-X.X.X.i386-pc.img.gz
   ```

3. Create the floppy 

   - Unix:   

     ```
     $ dd if=(your directory)/prex-X.X.X.i386-pc.img of=/dev/fd0
     ```

   - Windows   

     ```
     >rawritewin (your directory)/prex-X.X.X.i386-pc.img a:
     ```

## How to run Prex with Bochs?

### Installing Bochs

Bochs is an open-source x86 pc emulator, and you can run Prex with Bochs ons Windows/Linux. The Bochs latest release can be downloaded from [ http://bochs.sourceforge.net](http://bochs.sourceforge.net).

### Setting up for Bochs

The Prex demo disk is available for download. The disk image is 1.44M floppy image with FAT file format. And, this image can be used as a Bochs floppy image.

 You can setup Bochs for Prex by the following steps:

1. Download the binary file(*.img.gz) for the latest Prex boot floppy from the following web page.
    [  http://prex.sourceforge.net/downloads.htm](http://prex.sourceforge.net/downloads.html) 

2. Unpack the image. 

   ```
   $ gunzip prex-X.X.X.i386-pc.img.gz
   ```

3. Set the path for the floppy image in your Bochs setting file "bochsrc", like: 

   ```
   floppya: 1_44=(your directory)/prex-X.X.X.i386-pc.img, status=inserted
   ```

4. Set the bootable device in "bochsrc". 

   ```
   boot: floppy
   ```

5. Run Bochs. 

   ```
   $ bochs -q
   ```

## How to run Prex with QEMU?

 If you are using QEMU, the same image created for Bochs with above info can be used. You can simply try Prex with QEMU by the following command.

```
$ qemu -fda (your directory)/prex-X.X.X.i386-pc.img -localtime
```

## How to modify the OS boot image?

If you compile the Prex source with "make" command, the OS boot image is created as "prexos" in "img" directory. The file "prexos" must be placed in the root directory of the Prex disk. You can test your own Prex image by replacing the "prexos" in the floppy image.

To replace the file in the floppy image, "mtools" is useful. Before using "mcopy", the drive A must be point to the image file in "mtools.conf" as follows:

```
drive a: file="(your directory)/prex-X.X.X.i386-pc.img"
```

Then, the file copy can be performed by:

```
 $ mcopy -o prexos a:\
```

You can use this customized Prex image with Bochs, or you can create an actual bootable floppy disk and test it with the real PC hardware.

## How to install the boot sector?

In order to boot from the floppy disk, you must install the Prex boot sector named "bootsect.bin" into the 1st sector. The DOS program named "mkboot.com" is available to write this boot sector. You can create the Prex bootable floppy by the following steps.

1. Prepare a blank floppy disk. This must be formatted with 1.44M FAT file system.
2. Boot DOS, and put "bootsect.bin" and "mkboot.com" in the same directory.
3.  Type as follows:

```
a:\>mkboot a:
```

 You can perform these steps within Bochs if you have a DOS bootable image for Bochs. In this case, you have to specify the drive setting of Bochs as follow:

```
floppya: 1_44=dos-boot.img, status=inserted
floppyb: 1_44=(your directory)/prex-X.X.X.i386-pc.img, status=inserted
```

 Then, type:

```
a:\>mkboot b:
```

Note: You had better download an Prex bootable image rather than this method.

## Keyboard Interface

Some special keys are defined by the keyboard driver.

| Key          | Function                   |
| ------------ | -------------------------- |
| Alt+Ctrl+Del | Reboot                     |
| Ctrl+C       | Breakpoint                 |
| Ctrl+D       | Pause until next key input |
| F1           | Help for Fn dump keys      |
| F2           | Dump all threads           |
| F3           | Dump all tasks             |
| F4           | Dump memory information    |

## Debugging with Bochs

 Bochs has a capability to output the character to the console via i/o port 0xe9. To get your printf() or sys_log() message in the console, you must configure and rebuild Bochs/Prex as follows.

1. Bochs must be built with "--enable-port-e9-hack" option.
2. Prex must be built with enabling "BOCHS_OUTPUT" flag in "prex/src/arch/i386/diag.c".

The Bochs console is useful to debug kernel because you can browse or find the log message in the console window.

The Bochs internal debugger is also useful to debug kernel. It can be enabled with the following configuration.

```
$ ./configure --enable-debugger --enable-disasm --enable-port-e9-hack
```



Copyright© 2005-2009 Kohsuke Ohtani