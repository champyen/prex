# Handover Task Instruction: Prex+ Musca-B1 (Cortex-M33) QSPI XIP BSP

<GOAL>
Implement the ARM Musca-B1 (Cortex-M33) BSP support on Prex+ using a Position-Independent (PIC/ROPI) QSPI Flash Execute-in-Place (XIP) model.
</GOAL>

<BLUEPRINT_PLAN>
Please read, study, and follow our approved implementation plan located at:
file:///home/champ/workspace/gemini_playground/prex/qspi_sram_implementation_plan.md
</BLUEPRINT_PLAN>

<CODE_TO_STUDY_FIRST>
Before making any modifications, please read and analyze the following files and directories:

1. Prex+ Target Configuration: [conf/arm/musca-b1.base](file:///home/champ/workspace/gemini_playground/prex/conf/arm/musca-b1.base)
2. Prex+ Low-Level Startup: [bsp/hal/arm/arch/armv8-m/locore.S](file:///home/champ/workspace/gemini_playground/prex/bsp/hal/arm/arch/armv8-m/locore.S)
3. Prex+ Context Switching: [bsp/hal/arm/arch/armv8-m/context.c](file:///home/champ/workspace/gemini_playground/prex/bsp/hal/arm/arch/armv8-m/context.c)
4. Prex+ Bootloader ELF Loader: [bsp/boot/common/elf.c](file:///home/champ/workspace/gemini_playground/prex/bsp/boot/common/elf.c)
5. Prex+ Memory Allocators: [sys/mem/page.c](file:///home/champ/workspace/gemini_playground/prex/sys/mem/page.c) and [sys/mem/vm_nommu.c](file:///home/champ/workspace/gemini_playground/prex/sys/mem/vm_nommu.c)

6. Reference Zephyr Musca-B1 BSP DTS (Secure): file:///home/champ/workspace/gemini_playground/zephyr/boards/arm/v2m_musca_b1/v2m_musca_b1.dts
7. Reference Zephyr Musca-B1 BSP DTS (Non-Secure): file:///home/champ/workspace/gemini_playground/zephyr/boards/arm/v2m_musca_b1/v2m_musca_b1_musca_b1_ns.dts
8. Reference Zephyr SoC Config: file:///home/champ/workspace/gemini_playground/zephyr/soc/arm/musca/b1/soc.h

9. Environment and Build/Run Manual: [env.md](file:///home/champ/workspace/gemini_playground/prex/env.md)
10. Multi-Target Verification Script: [verify_all.sh](file:///home/champ/workspace/gemini_playground/prex/verify_all.sh)
</CODE_TO_STUDY_FIRST>

<ENVIRONMENT_AND_VERIFICATION>
Please refer to the environment files for manual build/run instructions and validation requirements:
1. **Manual Build and Run Information:** Detailed in [env.md](file:///home/champ/workspace/gemini_playground/prex/env.md). It outlines general build configurations, target parameters, and specifies the exact QEMU command and output redirection logic (using the required `sleep` statement) for running the `arm-musca-b1` target.
2. **Strict Verification Criteria:** Described in [verify_all.sh](file:///home/champ/workspace/gemini_playground/prex/verify_all.sh). It enforces the strict criteria of verification—booting successfully until the interactive shell prompt `[prex:/]#` is detected in the QEMU console log. Although the script currently runs target tests (excluding interactive boot-checks for `arm-musca-b1` prior to implementation), you must ensure that our final Cortex-M33 XIP implementation compiles cleanly and successfully runs to reach this prompt under the same rules.
</ENVIRONMENT_AND_VERIFICATION>

<CODE_MODIFICATION_RULES>
To protect target compatibility and keep code changes isolated:
1. **Prefer HAL Abstraction:** Unless the system design absolutely cannot fit, introduce architecture-dependent HAL functions first instead of modifying common code directly.
2. **Protect Common Code:** To keep other targets working, do not modify or remove common code directly. Use `#ifdef CONFIG_ARMV8M` to add or switch specific code paths for Cortex-M33.
3. **Preserve Other Targets:** Do not modify or remove any architecture-dependent or platform-dependent code for other targets.
</CODE_MODIFICATION_RULES>

<MANDATORY_WORKFLOW_RULES>
1. **Incremental Progress:** Do things incrementally and move forward with small steps.
2. **Verify Baseline First:** Before applying changes, run a baseline compilation check to make sure the repository currently builds cleanly:
   `LC_ALL=C ./configure --target=arm-musca-b1 --cross-prefix=arm-none-eabi && LC_ALL=C make clean && LC_ALL=C make`
3. **No Silent Resets:** Any command that discards or resets work (e.g. `git reset`, `git restore`) requires an Impact Analysis turn first. Never use `git clean`.
4. **Commit Control:** NEVER execute `git commit` or stage files with intent to commit without an explicit "LGTM" directive from the user.
5. **English Output:** Prepend `LC_ALL=C` to all shell commands.
</MANDATORY_WORKFLOW_RULES>

<EXECUTION_STAGES>
Please execute the implementation in the following sequential stages:

### Stage 1: Build Baseline Verification
* Run the baseline build check using the commands in `<MANDATORY_WORKFLOW_RULES>`.
* Confirm the baseline image builds successfully before editing any files.

### Stage 2: Compiler and Build Flags Configuration (Step 5.1) (Completed)
* Configure build settings to compile user tasks and libraries with GCC position-independent flags (`-fpic -msingle-pic-base -mpic-register=r9 -mno-pic-data-is-text-relative`).
* Configure linker scripts (`user.ld` and `user-nommu.ld`) to explicitly group and align GOT sections (`*(.got*)`).
* Configure build system to produce fully-linked position-independent ELF executables (`ET_EXEC`) for NOMMU rather than relocatable object files.

### Stage 3: ELF Loader Update for XIP (Step 5.2) (Completed)
* Modify `load_executable` in `bsp/boot/common/elf.c` to handle Execute-in-Place (XIP):
  - Do not copy `.text` or `.rodata` sections for XIP targets; instead, point `m->text` directly to their locations in QSPI Flash.
  - Relocate `.data`, `.got`, and `.bss` sections to SRAM.
  - Enable `--emit-relocs` in user-space `LDFLAGS` to preserve relocation tables in fully-linked executables.
  - Implement load-time relocations for SRAM-resident data and GOT tables:
    * Resolve `R_ARM_GOT_BREL` relocations by reading the GOT offset from the Flash-resident `.text` section and writing the runtime symbol address to the corresponding GOT entry in SRAM (ensuring no writes to Flash).
    * Resolve `.rel.data` (e.g. `R_ARM_ABS32`) absolute address relocations by updating their values directly in SRAM.
    * Identify the GOT base in SRAM using the offset of the separate `.got` section relative to `.data` in the ELF section headers.

### Stage 4: Execution Context & Stack Unification (Steps 5.3, 5.4, 5.5)
* **r9 register setup:** 
  - Add `vaddr_t got_base` to `struct task` in `sys/include/task.h` under `CONFIG_ARMV8M`.
  - Copy `mod->exidx_start` (the runtime GOT base address) to `task->got_base` during task bootstrapping/load time in `task.c`.
  - Set `u->r9` to `task->got_base` during user thread context setup in `context.c`.
* **MSP/PSP stack separation:** Rewrite `syscall_entry` and `syscall_ret` in `locore.S` to copy hardware exception frames between user stack (PSP) and kernel stack (MSP).
* **Context switching:** Implement context switching via `cpu_switch` in `locore.S` (which naturally preserves `r9` as part of `r4-r11`).

### Stage 5: System Configuration & Synchronization (Steps 5.6, 5.8, 5.9)
* **Interrupt priorities:** Update SysTick priority in `clock.c`.
* **Memory Barriers:** Add `dsb` and `isb` instructions to `sau_init` (after SAU enable) and `machine_startup` (after VTOR update) to enforce instruction pipeline synchronization.
* **Base configuration:** Confirm that `conf/arm/musca-b1.base` contains the correct `BOOTIMG_BASE`, `KERNEL_TEXT`, `ARM_VECTORS`, and `LDFLAGS` makeoptions.

### Stage 6: Validation and QEMU Testing (Step 5.7)
* Enable boot verification for `arm-musca-b1` by modifying `verify_all.sh` (line 99) to include it in the active targets list.
* Run `./verify_all.sh arm-musca-b1 nommu` to verify that the target compiles and successfully boots to the interactive shell prompt `[prex:/]#`.
</EXECUTION_STAGES>

Please begin by running a baseline build check, studying the files listed above, and presenting your analysis to the user. Do not write any code until you have confirmed the baseline compilation succeeds.
