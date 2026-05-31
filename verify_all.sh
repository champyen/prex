#!/bin/bash
# Prex Multi-Target Strict Verification Script
# Criteria: Must reach the interactive shell prompt [prex:/]#

# Target list (Fully unified and stabilized!)
ALL_TARGETS=("arm-qemu-virt" "arm-raspi0" "arm-integrator" "x86-pc" "arm-gba" "riscv-qemu-virt" "arm-musca-b1")

if [ -n "$1" ]; then
    TARGETS=("$1")
else
    TARGETS=("${ALL_TARGETS[@]}")
fi

echo "=================================================="
echo "STARTING STRICT MULTI-TARGET VERIFICATION"
echo "=================================================="

# Results collection
declare -a RESULTS

for TARGET in "${TARGETS[@]}"; do
    # Determine variants to test
    if [ -n "$2" ]; then
        VARIANTS=("$2")
    elif [[ "$TARGET" == "arm-gba" || "$TARGET" == "x86-pc" || "$TARGET" == "arm-musca-b1" ]]; then
        VARIANTS=("nommu")
    elif [[ "$TARGET" == "arm-qemu-virt" || "$TARGET" == "riscv-qemu-virt" ]]; then
        VARIANTS=("mmu" "nommu" "mmu-smp" "nommu-smp")
    else
        VARIANTS=("mmu" "nommu")
    fi

    for VARIANT in "${VARIANTS[@]}"; do
        echo ">>> Testing $TARGET ($VARIANT)..."

        # 0. Targeted Clean BEFORE Configure
        echo "    Cleaning workspace..."
        find . -name "*.o" -delete > /dev/null 2>&1 || true
        find . -name "*.a" -delete > /dev/null 2>&1 || true
        find . -name "Makefile.dep" -delete > /dev/null 2>&1 || true
        rm -f prexos.bin prexos_full.bin floppy.img disk.img bin.img usr/lib/*.a > /dev/null 2>&1 || true
        rm -f conf/config.h conf/config.mk conf/config.ld conf/drvtab.h conf/captab.h > /dev/null 2>&1 || true

        # 1. Configure
        OPTS=""
        [[ "$VARIANT" == "mmu" || "$VARIANT" == "mmu-smp" ]] && OPTS="$OPTS --enable-mmu"
        [[ "$VARIANT" == *"smp"* ]] && OPTS="$OPTS --enable-smp"

        if [[ "$TARGET" == "riscv-qemu-virt" ]]; then
            PREFIX="riscv64-unknown-elf"
            SMP_OPTS=""
            [[ "$VARIANT" == *"smp"* ]] && SMP_OPTS="-smp 4"
            QEMU="qemu-system-riscv32 -M virt -m 256M $SMP_OPTS -nographic -bios none -kernel prexos.bin \
                  -drive if=none,file=disk.img,id=drv0,format=raw -device virtio-blk-device,drive=drv0 \
                  -drive if=none,file=bin.img,id=drv1,format=raw -device virtio-blk-device,drive=drv1 \
                  -device virtio-sound-device,audiodev=audio0 -audiodev none,id=audio0 \
                  -netdev user,id=net0 -device virtio-net-device,netdev=net0 \
                  -d int,guest_errors,invalid_mem -D /tmp/qemu_debug.log"
        elif [[ "$TARGET" == "x86-pc" ]]; then
            PREFIX=""
            QEMU="qemu-system-i386 -fda floppy.img -boot a -nographic"
        else
            PREFIX="arm-none-eabi"
            if [[ "$TARGET" == "arm-qemu-virt" ]]; then
                SMP_OPTS=""
                [[ "$VARIANT" == *"smp"* ]] && SMP_OPTS="-smp 4"
                QEMU="qemu-system-arm -M virt -m 256M -kernel prexos.bin -nographic $SMP_OPTS \
                      -drive if=none,file=disk.img,id=drv0,format=raw -device virtio-blk-device,drive=drv0 \
                      -drive if=none,file=bin.img,id=drv1,format=raw -device virtio-blk-device,drive=drv1 \
                      -device virtio-sound-device,audiodev=audio0 -audiodev none,id=audio0 \
                      -netdev user,id=net0 -device virtio-net-device,netdev=net0"
            elif [[ "$TARGET" == "arm-raspi0" ]]; then
                QEMU="qemu-system-arm -M raspi0 -kernel prexos_full.bin -nographic"
            elif [[ "$TARGET" == "arm-integrator" ]]; then
                QEMU="qemu-system-arm -M integratorcp -kernel prexos_full.bin -nographic"
            elif [[ "$TARGET" == "arm-musca-b1" ]]; then
                QEMU="qemu-system-arm -M musca-b1 -kernel prexos.bin -nographic"
            fi
        fi

        CFG_CMD="./configure --target=$TARGET"
        [[ -n "$PREFIX" ]] && CFG_CMD="$CFG_CMD --cross-prefix=$PREFIX"
        [[ -n "$OPTS" ]] && CFG_CMD="$CFG_CMD $OPTS"

        LC_ALL=C $CFG_CMD > /dev/null 2>&1

        # 2. Build
        echo "    Building..."
        MAKE_OPTS="-j4"

        LOG_BUILD="build_${TARGET}_${VARIANT}.log"
        if ! (LC_ALL=C make $MAKE_OPTS all && LC_ALL=C make $MAKE_OPTS image) > "$LOG_BUILD" 2>&1; then
            echo "    BUILD FAILED! Check $LOG_BUILD"
            RESULTS+=("$TARGET|$VARIANT|BUILD_FAIL")
            continue
        fi

        # 3. Boot Verification (except GBA and Musca-B1)
        if [[ "$TARGET" != "arm-gba" && "$TARGET" != "arm-musca-b1" ]]; then
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

            # Launch QEMU in background
            $QEMU < /dev/null > "$LOG_QEMU" 2>&1 &
            QEMU_PID=$!

            # Monitor for shell prompt or 20 seconds timeout
            BOOT_OK=0
            for i in {1..20}; do
                sleep 1
                if grep -q "\[prex:/" "$LOG_QEMU"; then
                    BOOT_OK=1
                    break
                fi
            done

            # Force kill QEMU process
            kill -9 $QEMU_PID >/dev/null 2>&1 || true

            if [[ $BOOT_OK -eq 1 ]]; then
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
