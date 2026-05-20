#!/bin/bash
# Prex Multi-Target Strict Verification Script
# Criteria: Must reach the interactive shell prompt [prex:/]#

# Target list
TARGETS=("arm-qemu-virt" "arm-raspi0" "arm-integrator" "x86-pc" "arm-gba" "riscv-qemu-virt")

echo "=================================================="
echo "STARTING STRICT MULTI-TARGET VERIFICATION"
echo "=================================================="

# Results collection
declare -a RESULTS

for TARGET in "${TARGETS[@]}"; do
    # Determine variants to test
    if [[ "$TARGET" == "arm-gba" || "$TARGET" == "riscv-qemu-virt" ]]; then
        VARIANTS=("nommu")
    else
        VARIANTS=("mmu" "nommu")
    fi
    
    for VARIANT in "${VARIANTS[@]}"; do
        echo ">>> Testing $TARGET ($VARIANT)..."
        
        # 0. Aggressive Clean BEFORE Configure
        echo "    Cleaning workspace..."
        find . -name "*.o" -delete
        find . -name "*.a" -delete
        find . -name "Makefile.dep" -delete
        rm -f prexos.bin prexos_full.bin floppy.img disk.img bin.img
        
        # 1. Configure
        OPTS=""
        [[ "$VARIANT" == "mmu" ]] && OPTS="--enable-mmu"
        
        if [[ "$TARGET" == "riscv-qemu-virt" ]]; then
            PREFIX="riscv64-unknown-elf"
            QEMU="qemu-system-riscv32 -M virt -m 256M -nographic -bios none -kernel prexos.bin"
        elif [[ "$TARGET" == "x86-pc" ]]; then
            PREFIX=""
            QEMU="qemu-system-i386 -fda floppy.img -boot a -nographic"
        else
            PREFIX="arm-none-eabi"
            if [[ "$TARGET" == "arm-qemu-virt" ]]; then
                QEMU="qemu-system-arm -M virt -m 256M -kernel prexos.bin -nographic \
                      -drive if=none,file=disk.img,id=drv0,format=raw -device virtio-blk-device,drive=drv0 \
                      -drive if=none,file=bin.img,id=drv1,format=raw -device virtio-blk-device,drive=drv1 \
                      -device virtio-sound-device,audiodev=audio0 -audiodev pa,id=audio0 \
                      -netdev user,id=net0 -device virtio-net-device,netdev=net0"
            elif [[ "$TARGET" == "arm-raspi0" ]]; then
                QEMU="qemu-system-arm -M raspi0 -kernel prexos_full.bin -nographic"
            elif [[ "$TARGET" == "arm-integrator" ]]; then
                QEMU="qemu-system-arm -M integratorcp -kernel prexos_full.bin -nographic"
            fi
        fi

        CFG_CMD="./configure --target=$TARGET"
        [[ -n "$PREFIX" ]] && CFG_CMD="$CFG_CMD --cross-prefix=$PREFIX"
        [[ -n "$OPTS" ]] && CFG_CMD="$CFG_CMD $OPTS"

        LC_ALL=C $CFG_CMD > /dev/null 2>&1

        # 2. Build
        echo "    Building..."
        MAKE_OPTS="-j4"
        [[ "$TARGET" == "riscv-qemu-virt" ]] && MAKE_OPTS="-j1"
        
        LOG_BUILD="build_${TARGET}_${VARIANT}.log"
        if ! LC_ALL=C make $MAKE_OPTS all image > "$LOG_BUILD" 2>&1; then
            echo "    BUILD FAILED! Check $LOG_BUILD"
            RESULTS+=("$TARGET|$VARIANT|BUILD_FAIL")
            continue
        fi

        # 3. Boot Verification (except GBA)
        if [[ "$TARGET" != "arm-gba" ]]; then
            # x86 needs floppy.img
            if [[ "$TARGET" == "x86-pc" ]]; then
                echo "    Creating floppy.img..."
                dd if=/dev/zero of=floppy.img bs=1024 count=1440 > /dev/null 2>&1
                mkfs.fat -F 12 floppy.img > /dev/null 2>&1
                dd if=bsp/boot/x86/tools/bootsect/bootsect.bin of=floppy.img bs=1 count=3 conv=notrunc > /dev/null 2>&1
                dd if=bsp/boot/x86/tools/bootsect/bootsect.bin of=floppy.img bs=1 skip=62 seek=62 conv=notrunc > /dev/null 2>&1
                mcopy -i floppy.img prexos.bin ::/PREXOS > /dev/null 2>&1
            fi

            echo "    Booting..."
            LOG_QEMU="qemu_${TARGET}_${VARIANT}.log"
            timeout 30 $QEMU < /dev/null > "$LOG_QEMU" 2>&1 || true
            
            if grep -q "\[prex:/" "$LOG_QEMU"; then
                echo "    BOOT SUCCESS: Shell prompt detected."
                RESULTS+=("$TARGET|$VARIANT|PASS")
            else
                echo "    BOOT FAILED! Shell prompt NOT detected in $LOG_QEMU"
                RESULTS+=("$TARGET|$VARIANT|BOOT_FAIL")
            fi
        else
            echo "    BUILD SUCCESS (GBA is build-only)."
            RESULTS+=("$TARGET|$VARIANT|PASS")
        fi
    done
done

echo ""
echo "=================================================="
echo "           VERIFICATION SCOREBOARD"
echo "=================================================="
printf "%-20s | %-10s | %-10s\n" "TARGET" "VARIANT" "RESULT"
echo "--------------------------------------------------"
for entry in "${RESULTS[@]}"; do
    IFS='|' read -r t v r <<< "$entry"
    printf "%-20s | %-10s | %-10s\n" "$t" "$v" "$r"
done
echo "=================================================="
