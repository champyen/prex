#!/bin/bash
# Prex RISC-V Multi-Variant Verification Script
# Criteria: Must reach the interactive shell prompt [prex:/]#

# Target list
TARGETS=("riscv-qemu-virt")

echo "=================================================="
echo "STARTING RISC-V MULTI-VARIANT VERIFICATION"
echo "=================================================="

# Results collection
declare -a RESULTS

for TARGET in "${TARGETS[@]}"; do
    VARIANTS=("mmu" "nommu")
    
    for VARIANT in "${VARIANTS[@]}"; do
        echo ">>> Testing $TARGET ($VARIANT)..."
        
        # 0. Clean workspace
        echo "    Cleaning workspace..."
        make clean > /dev/null 2>&1
        find . -name "*.o" -delete
        find . -name "*.a" -delete
        find . -name "Makefile.dep" -delete
        rm -f prexos.bin prexos_full.bin disk.img bin.img
        
        # 1. Configure
        OPTS=""
        [[ "$VARIANT" == "mmu" ]] && OPTS="$OPTS --enable-mmu"
        PREFIX="riscv64-unknown-elf"
        
        CFG_CMD="./configure --target=$TARGET --cross-prefix=$PREFIX $OPTS"
        echo "    Configuring: $CFG_CMD"
        LC_ALL=C $CFG_CMD > /dev/null 2>&1

        # 2. Build
        echo "    Building..."
        LOG_BUILD="build_${TARGET}_${VARIANT}.log"
        if ! LC_ALL=C make -j4 all image > "$LOG_BUILD" 2>&1; then
            echo "    BUILD FAILED! Check $LOG_BUILD"
            RESULTS+=("$TARGET|$VARIANT|BUILD_FAIL")
            continue
        fi

        # 3. Boot Verification
        echo "    Booting..."
        QEMU="qemu-system-riscv32 -M virt -m 256M -nographic -bios none -kernel prexos.bin \
              -drive if=none,file=disk.img,id=drv0,format=raw -device virtio-blk-device,drive=drv0 \
              -drive if=none,file=bin.img,id=drv1,format=raw -device virtio-blk-device,drive=drv1 \
              -device virtio-sound-device,audiodev=audio0 -audiodev none,id=audio0 \
              -netdev user,id=net0 -device virtio-net-device,netdev=net0"
        LOG_QEMU="qemu_${TARGET}_${VARIANT}.log"
        
        # Run QEMU with a timeout
        LC_ALL=C timeout 45 $QEMU < /dev/null > "$LOG_QEMU" 2>&1 || true


        
        if grep -q "\[prex:/" "$LOG_QEMU"; then
            echo "    BOOT SUCCESS: Shell prompt detected."
            RESULTS+=("$TARGET|$VARIANT|PASS")
        else
            echo "    BOOT FAILED! Shell prompt NOT detected in $LOG_QEMU"
            tail -n 10 "$LOG_QEMU"
            RESULTS+=("$TARGET|$VARIANT|BOOT_FAIL")
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
