/*
 * Copyright 2015 Stephen Street <stephen@redrocketcomputing.com>
 * 
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. 
 */

/*
 * Safety boundaries for memory access:
 * - PAGE_SIZE: Minimum safe address (skips vector table/NULL page).
 * - USERLIMIT: Architectural limit for address space access.
 */

#include <kernel.h>
#include <machine/memory.h>

#ifdef CONFIG_KERNEL_BACKTRACE

#ifdef __arm__

typedef struct backtrace_frame
{
	uint32_t r7;
	uint32_t r11;
	uint32_t sp;
	uint32_t lr;
	uint32_t pc;
} backtrace_frame_t;

typedef struct unwind_control_block
{
	uint32_t vrs[16];
	const uint32_t *current;
	int remaining;
	int byte;
} unwind_control_block_t;

typedef struct unwind_index
{
	uint32_t addr_offset;
	uint32_t insn;
} unwind_index_t;

/* These symbols point to the unwind index and should be provide by the linker script */
extern const unwind_index_t __exidx_start[];
extern const unwind_index_t __exidx_end[];

#include <hal.h>
#include <sys/bootinfo.h>

static inline __attribute__((always_inline)) uint32_t prel31_to_addr(const uint32_t *prel31)
{
	int32_t offset = (((int32_t)(*prel31)) << 1) >> 1;
	return (uint32_t)prel31 + offset;
}

static const struct unwind_index *unwind_search_index(const unwind_index_t *start, const unwind_index_t *end, uint32_t ip)
{
	const struct unwind_index *middle;

	if (start >= end)
		return NULL;

	/* Perform a binary search of the unwind index */
	while (start < end - 1) {
		middle = start + ((end - start + 1) >> 1);
		if (ip < prel31_to_addr(&middle->addr_offset))
			end = middle;
		else
			start = middle;
	}
	return start;
}

static const struct unwind_index *unwind_search_all_indices(uint32_t ip)
{
	const struct unwind_index *index;
	struct module *m;
	struct bootinfo *bi;

	machine_bootinfo(&bi);

	/* 1. Search the core kernel's table (usually linked-in) */
	index = unwind_search_index(__exidx_start, __exidx_end, ip);
	if (index && ip >= prel31_to_addr(&index->addr_offset)) {
		if (ip < (uint32_t)bi->kernel.text + bi->kernel.textsz)
			return index;
	}

	/* 2. Search the driver module table */
	m = &bi->driver;
	if (m->exidx_start && m->exidx_size > 0) {
		const unwind_index_t *start = (const unwind_index_t *)m->exidx_start;
		const unwind_index_t *end = (const unwind_index_t *)(m->exidx_start + m->exidx_size);
		index = unwind_search_index(start, end, ip);
		if (index && ip >= prel31_to_addr(&index->addr_offset)) {
			if (ip < (uint32_t)m->text + m->textsz)
				return index;
		}
	}

#ifndef CONFIG_MMU
	/* 3. Search boot tasks tables (for NOMMU support) */
	for (int i = 0; i < bi->nr_tasks; i++) {
		m = &bi->tasks[i];
		if (m->exidx_start && m->exidx_size > 0) {
			const unwind_index_t *start = (const unwind_index_t *)m->exidx_start;
			const unwind_index_t *end = (const unwind_index_t *)(m->exidx_start + m->exidx_size);
			index = unwind_search_index(start, end, ip);
			if (index && ip >= prel31_to_addr(&index->addr_offset)) {
				if (ip < (uint32_t)m->text + m->textsz)
					return index;
			}
		}
	}
#endif

	return NULL;
}

const char *backtrace_name(uint32_t address)
{
	address &= ~1U; /* Clear Thumb bit */
	if (address < PAGE_SIZE) /* Safety check */
		return "";

	uint32_t flag_word = *(uint32_t *)(address - 4);
	if ((flag_word & 0xff000000) == 0xff000000) {
		const char *name = (const char *)(address - 4 - (flag_word & 0x00ffffff));
		if ((uint32_t)name >= PAGE_SIZE)
			return name;
	}
	return "";
}

static int unwind_get_next_byte(unwind_control_block_t *ucb)
{
	int instruction;

	/* Are there more instructions */
	if (ucb->remaining == 0)
		return -1;

	/* Extract the current instruction */
	instruction = ((*ucb->current) >> (ucb->byte << 3)) & 0xff;

	/* Move the next byte */
	--ucb->byte;
	if (ucb->byte < 0) {
		++ucb->current;
		ucb->byte = 3;
	}
	--ucb->remaining;

	return instruction;
}

static int unwind_control_block_init(unwind_control_block_t *ucb, const uint32_t *instructions, const backtrace_frame_t *frame)
{
	/* Initialize control block */
	memset(ucb, 0, sizeof(unwind_control_block_t));
	ucb->current = instructions;

	/* Is the a short unwind description */
	if ((*instructions & 0xff000000) == 0x80000000) {
		ucb->remaining = 3;
		ucb->byte = 2;
	/* Is the a long unwind description */
	} else if ((*instructions & 0xff000000) == 0x81000000) {
		ucb->remaining = ((*instructions & 0x00ff0000) >> 14) + 2;
		ucb->byte = 1;
	} else
		return -1;

	/* Initialize the virtual register set */
	if (frame) {
		ucb->vrs[7] = frame->r7;
		ucb->vrs[11] = frame->r11;
		ucb->vrs[13] = frame->sp;
		ucb->vrs[14] = frame->lr;
		ucb->vrs[15] = 0;
	}

	/* All good */
	return 0;
}

static int unwind_execute_instruction(unwind_control_block_t *ucb)
{
	int instruction;
	uint32_t mask;
	uint32_t reg;
	uint32_t *vsp;

	/* Consume all instruction byte */
	while ((instruction = unwind_get_next_byte(ucb)) != -1) {

		if ((instruction & 0xc0) == 0x00) {
			/* vsp = vsp + (xxxxxx << 2) + 4 */
			ucb->vrs[13] += ((instruction & 0x3f) << 2) + 4;

		} else if ((instruction & 0xc0) == 0x40) {
			/* vsp = vsp - (xxxxxx << 2) - 4 */
			ucb->vrs[13] -= ((instruction & 0x3f) << 2) + 4;

		} else if ((instruction & 0xf0) == 0x80) {
			/* pop under mask {r15-r12},{r11-r4} or refuse to unwind */
			instruction = instruction << 8 | unwind_get_next_byte(ucb);

			/* Check for refuse to unwind */
			if (instruction == 0x8000)
				return 0;

			/* Pop registers using mask */
			vsp = (uint32_t *)ucb->vrs[13];
			mask = instruction & 0xfff;

			/* Loop through the mask */
			reg = 4;
			while (mask != 0) {
				if ((mask & 0x001) != 0) {
					if ((uint32_t)vsp < PAGE_SIZE) return -1;
					ucb->vrs[reg] = *vsp++;
				}
				mask = mask >> 1;
				++reg;
			}

			/* Update the vrs sp as usual if r13 (sp) was not in the mask,
			 * otherwise leave the popped r13 as is. */
			if ((mask & (1 << (13 - 4))) == 0)
				ucb->vrs[13] = (uint32_t)vsp;

		} else if ((instruction & 0xf0) == 0x90 && instruction != 0x9d && instruction != 0x9f) {
			/* vsp = r[nnnn] */
			ucb->vrs[13] = ucb->vrs[instruction & 0x0f];

		} else if ((instruction & 0xf0) == 0xa0) {
			/* pop r4-r[4+nnn] or pop r4-r[4+nnn], r14*/
			vsp = (uint32_t *)ucb->vrs[13];

			for (reg = 4; reg <= (uint32_t)((instruction & 0x07) + 4); ++reg) {
				if ((uint32_t)vsp < PAGE_SIZE) return -1;
				ucb->vrs[reg] = *vsp++;
			}

			if (instruction & 0x08) {
				if ((uint32_t)vsp < PAGE_SIZE) return -1;
				ucb->vrs[14] = *vsp++;
			}

			ucb->vrs[13] = (uint32_t)vsp;

		} else if (instruction == 0xb0) {
			/* finished */
			if (ucb->vrs[15] == 0)
				ucb->vrs[15] = ucb->vrs[14];

			/* All done unwinding */
			return 0;

		} else if (instruction == 0xb1) {
			/* pop register under mask {r3,r2,r1,r0} */
			vsp = (uint32_t *)ucb->vrs[13];
			mask = unwind_get_next_byte(ucb);

			reg = 0;
			while (mask != 0) {
				if ((mask & 0x01) != 0) {
					if ((uint32_t)vsp < PAGE_SIZE) return -1;
					ucb->vrs[reg] = *vsp++;
				}
				mask = mask >> 1;
				++reg;
			}
			ucb->vrs[13] = (uint32_t)vsp;

		} else if (instruction == 0xb2) {
			/* vps = vsp + 0x204 + (uleb128 << 2) */
			ucb->vrs[13] += 0x204 + (unwind_get_next_byte(ucb) << 2);

		} else if (instruction == 0xb3 || instruction == 0xc8 || instruction == 0xc9) {
			/* pop VFP double-precision registers */
			vsp = (uint32_t *)ucb->vrs[13];

			/* D[ssss]-D[ssss+cccc] or D[16+sssss]-D[16+ssss+cccc] as pushed by VPUSH or FSTMFDX */
			vsp += 2 * ((unwind_get_next_byte(ucb) & 0x0f) + 1);


			if (instruction == 0xb3) {
				/* as pushed by FSTMFDX */
				vsp++;
			}

			ucb->vrs[13] = (uint32_t)vsp;

		} else if ((instruction & 0xf8) == 0xb8 || (instruction & 0xf8) == 0xd0) {
			/* pop VFP double-precision registers */
			vsp = (uint32_t *)ucb->vrs[13];

			/* D[8]-D[8+nnn] as pushed by VPUSH or FSTMFDX */
			vsp += 2 * ((instruction & 0x07) + 1);

			if ((instruction & 0xf8) == 0xb8) {
				/* as pushed by FSTMFDX */
				vsp++;
			}

			ucb->vrs[13] = (uint32_t)vsp;

		} else
			return -1;
	}

	return instruction != -1;
}

static int unwind_frame(backtrace_frame_t *frame)
{
	unwind_control_block_t ucb;
	const unwind_index_t *index;
	const uint32_t *instructions;
	int execution_result;

	/* Search the unwind index for the matching unwind table */
	index = unwind_search_all_indices(frame->pc);
	if (index == NULL)
		return -1;

	/* Make sure we can unwind this frame */
	if (index->insn == 0x00000001)
		return 0;

	/* Get the pointer to the first unwind instruction */
	if (index->insn & 0x80000000)
		instructions = &index->insn;
	else
		instructions = (uint32_t *)prel31_to_addr(&index->insn);

	if (!instructions || (uint32_t)instructions < PAGE_SIZE)
		return -1;

	/* Initialize the unwind control block */
	if (unwind_control_block_init(&ucb, instructions, frame) < 0)
		return -1;

	/* Execute the unwind instructions */
	while ((execution_result = unwind_execute_instruction(&ucb)) > 0);
	if (execution_result == -1)
		return -1;

	/* Set the virtual pc to the virtual lr if this is the first unwind */
	if (ucb.vrs[15] == 0)
		ucb.vrs[15] = ucb.vrs[14];

	/* We are done if current frame pc is equal to the virtual pc, prevent infinite loop */
	if (frame->pc == ucb.vrs[15])
		return 0;

	/* Update the frame */
	frame->r7 = ucb.vrs[7];
	frame->r11 = ucb.vrs[11];
	frame->sp = ucb.vrs[13];
	frame->lr = ucb.vrs[14];
	frame->pc = ucb.vrs[15];

	/* All good */
	return 1;
}

static int _backtrace_unwind(backtrace_t *buffer, int size, backtrace_frame_t *frame)
{
	int count = 0;

	/* Initialize the backtrace frame buffer */
	memset(buffer, 0, sizeof(backtrace_t) * size);

	/* Unwind all frames */
	do {
		if (frame->pc == 0) {
			break;
		}

		if (frame->pc == 0x00000001) {
			break;
		}

		/* Find the unwind index of the current frame pc */
		const unwind_index_t *index = unwind_search_all_indices(frame->pc);

		/* Clear last bit (Thumb indicator) */
		uint32_t pc = frame->pc & 0xfffffffeU;

		/* Generate the backtrace information */
		buffer[count].address = (void *)pc;
		if (index) {
			buffer[count].function = (void *)prel31_to_addr(&index->addr_offset);
			buffer[count].name = backtrace_name((uint32_t)buffer[count].function);
		} else {
			buffer[count].function = NULL;
			buffer[count].name = "";
		}

		/* Next backtrace frame */
		++count;

	} while (unwind_frame(frame) > 0 && count < size);

	/* All done */
	return count;
}

int backtrace_unwind_frame(backtrace_t *buffer, int size, uint32_t pc, uint32_t lr, uint32_t sp, uint32_t r7, uint32_t r11)
{
	/* Initialize the stack frame */
	backtrace_frame_t frame;
	frame.sp = sp;
	frame.r7 = r7;
	frame.r11 = r11;
	frame.lr = lr;
	frame.pc = pc;

	/* Let it rip */
	return _backtrace_unwind(buffer, size, &frame);
}

int backtrace_unwind(backtrace_t *buffer, int size)
{
	/* Initialize the stack frame */
	backtrace_frame_t frame;
	register uint32_t sp __asm__("sp");
	register uint32_t r7 __asm__("r7");
	register uint32_t r11 __asm__("r11");

	/* Get the current pc and lr */
	__asm__ volatile("mov %0, pc" : "=r"(frame.pc));
	__asm__ volatile("mov %0, lr" : "=r"(frame.lr));

	frame.sp = sp;
	frame.r7 = r7;
	frame.r11 = r11;

	/* Let it rip */
	return _backtrace_unwind(buffer, size, &frame);
}

const char *backtrace_function_name(uint32_t pc)
{
	const unwind_index_t *index = unwind_search_all_indices(pc);
	if (!index)
		return "";

	return backtrace_name(prel31_to_addr(&index->addr_offset));
}

void backtrace_save(void)
{
}

/*
 * __aeabi_unwind_cpp_pr0, __aeabi_unwind_cpp_pr1 and __aeabi_unwind_cpp_pr2 
 * are the ARM EABI defined C++ personality routines.
 */
void __aeabi_unwind_cpp_pr0(void) {}
void __aeabi_unwind_cpp_pr1(void) {}
void __aeabi_unwind_cpp_pr2(void) {}

#endif /* __arm__ */

#ifdef __x86__

static inline int safe_read_ptr(uint32_t *addr, uint32_t *val)
{
	if ((uint32_t)addr < PAGE_SIZE)
		return -1;
	*val = *addr;
	return 0;
}

int backtrace_unwind_frame(backtrace_t *buffer, int size, uint32_t pc, uint32_t lr, uint32_t sp, uint32_t r7, uint32_t r11)
{
	uint32_t *fp = (uint32_t *)r11; /* ebp is passed in r11 slot for x86 */
	int count = 0;

	memset(buffer, 0, sizeof(backtrace_t) * size);

	while (count < size) {
		uint32_t next_fp, ret_addr;

		if (safe_read_ptr(fp, &next_fp) < 0)
			break;
		if (safe_read_ptr(fp + 1, &ret_addr) < 0)
			break;

		if (next_fp == 0 || ret_addr == 0)
			break;

		buffer[count].address = (void *)ret_addr;
		buffer[count].function = NULL;
		buffer[count].name = "";

		fp = (uint32_t *)next_fp;
		count++;
	}

	return count;
}

int backtrace_unwind(backtrace_t *buffer, int size)
{
	register uint32_t ebp __asm__("ebp");

	/* We pass ebp in the r11 argument slot */
	return backtrace_unwind_frame(buffer, size, 0, 0, 0, 0, ebp);
}

const char *backtrace_function_name(uint32_t pc)
{
	return "";
}

const char *backtrace_name(uint32_t address)
{
	return "";
}

void backtrace_save(void)
{
}

#endif /* __x86__ */

#endif /* CONFIG_KERNEL_BACKTRACE */
