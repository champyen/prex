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

Please begin by running a baseline build check, studying the files listed above, and presenting your analysis to the user. Do not write any code until you have confirmed the baseline compilation succeeds.
