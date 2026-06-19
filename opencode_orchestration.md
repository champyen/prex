# Antigravity-OpenCode Orchestration: Token-Saving Workflow

This document serves as a reference guide and system instruction template. You can copy/paste the prompt in Section 1 into the chat at the start of any future session with **Antigravity-cli** to immediately initialize the token-saving, local-delegation workflow.

---

## 1. Initializer Prompt for Antigravity

Copy and paste the following block at the beginning of a new session:

```markdown
We are using the Antigravity-OpenCode Orchestration workflow to save token usage.
Please follow these guidelines:
1. Do not generate large code blocks directly in this chat.
2. Act as the Architect/Orchestrator: Analyze files, check compile errors, and design prompts.
3. Plan and breakdown all tasks into a very fine granularity before generating prompts (since the free models perform best on highly focused, single-step prompts).
4. Delegate all file-writing, editing, and boilerplate generation tasks to the local OpenCode CLI tool.
5. When writing code, execute OpenCode as a background command:
   LC_ALL=C /home/champ/.opencode/bin/opencode run -m <model> "<prompt>"
   
Select the model based on the task:
- `opencode/mimo-v2.5-free`: For general programming, C/C++ logic, and Zig.
- `opencode/nemotron-3-ultra-free`: For low-level assembly, FFI mappings, DMA/hardware configurations, and math.
- `opencode/deepseek-v4-flash-free`: For quick code edits, refactoring, and fixing compile errors.

Once OpenCode completes, inspect the output/diff, run verification tests, and report the results.
```

---

## 2. CLI Reference for the Orchestrator

The following commands are used by the orchestrator to interact with your local OpenCode environment:

### 2.1 Get Configured Free Models
```bash
LC_ALL=C /home/champ/.opencode/bin/opencode models
```

### 2.2 Run a Task in the Background (Non-Interactive)
To generate code and write it directly to a file, trigger OpenCode in non-interactive mode. (If the task runs longer than 2 seconds, Antigravity will automatically manage it as a background task).
```bash
LC_ALL=C /home/champ/.opencode/bin/opencode run -m opencode/mimo-v2.5-free "Please implement the core functions in '/path/to/file.c' according to the specifications... Use your file writing tools to write it."
```

---

## 3. Best Practices for Hybrid Development

### A. Task Granularity (Crucial for Free Models)
Because the free models available in OpenCode have slightly lower logic capacities than frontier models like Gemini 1.5 Pro or Gemini 3.5 Flash, they can easily get confused by complex instructions. 
* **The Rule:** The orchestrator must break down any coding request into the smallest possible logical increments (e.g. implementing one function at a time, or writing imports first, rather than a full script in one go).

### B. Context Grounding
Because free models have smaller context windows and can be prone to API hallucination, the orchestrator should construct **highly targeted prompts**. Always include:
1. **Target file path** where the code must be written.
2. **Freestanding constraints** (e.g. no dynamic memory allocation for RTOS, specific fixed-point math).
3. **Reference signatures** or C headers (copy-paste only the necessary declarations).

### C. LSP Integration (Prex/Genesis)
To ensure OpenCode edits are error-free before compile tests, verify that the Language Server Protocol (LSP) configuration in `~/.config/opencode/.opencode.json` includes the correct include headers:
- **For Prex:** `-I/home/champ/workspace/gemini_playground/prex/bsp/drv/include`
- **For SGDK:** `-I/home/champ/workspace/gemini_playground/megadrive/sgdk/inc`

### D. Iterative Error Fixing (Self-Correction Loop)
Instead of manual copy-pasting, delegate compilation and error fixing directly to OpenCode:
1. Attach reference or source files using the `-f` / `--file` option.
2. Instruct OpenCode to run verification commands (e.g., `make` or `./verify_all.sh`) using its command tool.
3. Direct OpenCode to check the compiler stdout/stderr, edit the target file to fix errors, and build again in a loop until verification passes.
4. For non-interactive background runs, append `--dangerously-skip-permissions` to auto-approve command execution without blocking.
