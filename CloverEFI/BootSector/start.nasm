
;
; Parameters
;   X64 - 64 bit target
;   LEGACY_A20 - use slow A20 Gate
;   CHARACTER_TO_SHOW - character to display
;   FORCE_TEXT_MODE - switch to 80x25 mono mode
;   USB_LOW_EBDA - low-ebda mode
;   GENPAGE - genpage mode
;

%ifdef LEGACY_A20
DELAY_PORT:		equ 0xed	; Port to use for 1uS delay
KBD_CONTROL_PORT:	equ 0x60	; 8042 control port
KBD_STATUS_PORT:	equ 0x64	; 8042 status port
WRITE_DATA_PORT_CMD:	equ 0xd1	; 8042 command to write the data port
ENABLE_A20_CMD:		equ 0xdf	; 8042 command to enable A20
%else
FAST_ENABLE_A20_PORT:	equ 0x92
FAST_ENABLE_A20_MASK:	equ 2
%endif
BASE_ADR_16:		equ 0x0200
SIZE_TO_STACK_16:	equ 0x0fe0 - BASE_ADR_16
IA32_EFER:		equ 0xC0000080
%ifndef CHARACTER_TO_SHOW
  %ifdef X64
    %define CHARACTER_TO_SHOW '7'
  %else
    %define CHARACTER_TO_SHOW '3'
  %endif
%endif

%assign GDT_DESC_SIZE 8
%macro GDT_DESC 2
	dw 0xFFFF, 0
	db 0, %1, %2, 0
%endmacro

%ifdef X64
  %assign IDT_DESC_SIZE 16
  %macro IDT_DESC 0
	dw 0, SYS_CODE64_SEL
	db 0, 0x8e
	dw 0
	dd 0, 0
  %endmacro
%else
  %assign IDT_DESC_SIZE 8
  %macro IDT_DESC 0
	dw 0, SYS_CODE_SEL
	db 0, 0x8e
	dw 0
  %endmacro
%endif

%ifdef X64
  %ifndef GENPAGE
	section .pagezero start=0
	times BASE_ADR_16 db 0
  %endif
%else
  %undef GENPAGE
%endif

	bits 16

	section .text start=BASE_ADR_16

global _start
_start:
	jmp	.SkipLabel
%ifdef X64
	db	'CLOVERX64   '	; Bootloader Label
%else
	db	'CLOVERIA32  '	; Bootloader Label
%endif
.SkipLabel:
	mov	ax, cs
	mov	ds, ax
	mov	es, ax
	mov	ss, ax
	mov	sp, MyStack

;
; Retrieve Bios Memory Map
;
	xor	ebx, ebx
	lea	edi, [MemoryMap]
.MemMapLoop:
	mov	eax, 0xe820
	mov	ecx, 20
	mov	edx, 0x534d4150		; SMAP
	int	0x15
        jc	.MemMapDone
	add	di, 20
	test	ebx, ebx
	jnz	.MemMapLoop
.MemMapDone:
	sub	di, MemoryMap		; Get the address of the memory map
	mov	[MemoryMapSize], edi	; Save the size of the memory map

;
; Rebase Self
;
	xor	ebx, ebx
	mov	bx, cs
	shl	ebx, 4
	add	[gdtr + 2], ebx
	add	[idtr + 2], ebx
	add	[.JumpTo32BitProtectedMode], ebx
%ifdef X64
	add	[.JumpToLongMode], ebx
%endif

;
; Enable A20 Gate
;
	mov	ax, 0x2401
	int	0x15
	jnc	.A20GateEnabled

;
; If INT 15 Function 2401 is not supported, then attempt to Enable A20 manually.
;

%ifdef LEGACY_A20
;
; Legacy A20gate
;
	call	Empty8042InputBuffer	; Empty the Input Buffer on the 8042 controller
	jnz	.Timeout8042		; Jump if the 8042 timed out
	out	DELAY_PORT, ax		; Delay 1 uS
	mov	al, WRITE_DATA_PORT_CMD	; 8042 cmd to write output port
	out	KBD_STATUS_PORT, al	; Send command to the 8042
	call	Empty8042InputBuffer	; Empty the Input Buffer on the 8042 controller
	jnz	.Timeout8042		; Jump if the 8042 timed out
	mov	al, ENABLE_A20_CMD	; gate address bit 20 on
	out	KBD_CONTROL_PORT,al	; Send command to thre 8042
	call	Empty8042InputBuffer	; Empty the Input Buffer on the 8042 controller
	mov	cx, 25			; Delay 25 uS for the command to complete on the 8042
.Delay25uS:
	out	DELAY_PORT, ax		; Delay 1 uS
	loop	.Delay25uS
.Timeout8042:

%else
;
; WIKI - fast A20gate
;
	in	al, FAST_ENABLE_A20_PORT
	or	al, FAST_ENABLE_A20_MASK
	out	FAST_ENABLE_A20_PORT, al

%endif

.A20GateEnabled:

%ifdef GENPAGE
;
; Create Page Table
;
	call	CreatePageTable
%endif

%ifdef FORCE_TEXT_MODE
;
; Switch to 80x25 mono text mode (2)
;
	mov	ax, 2
	int	0x10
%endif

;
; Display CHARACTER_TO_SHOW
;
	mov	bx, 0x000F
	mov	ax, 0x0E00 | (CHARACTER_TO_SHOW & 255)
	int	0x10

%ifndef X64
	mov	bx, LINEAR_SEL	; Flat data descriptor
%endif

;
; DISABLE INTERRUPTS - Entering Protected Mode
;
	cli

%ifdef GENPAGE
;
; Ready Address of Page Table in EDX
;
	movzx	edx, word [PageTableSegment]
	shl	edx, 4
%endif

;
; load GDT
;
	lgdt [gdtr]

%ifndef X64
;
; load IDT
;
	lidt [idtr]
%endif

;
; Enable Protected Mode (set CR0.PE=1)
;
	mov	eax, cr0
	or	al, 1
	mov	cr0, eax

.JumpTo32BitProtectedMode:	equ $ + 2
%ifndef X64
	jmp	dword LINEAR_CODE_SEL:(BlockSignature + 2)
%else
	jmp	dword LINEAR_CODE_SEL:.In32BitProtectedMode
.In32BitProtectedMode:

	bits 32
;
; Entering Long Mode
;
	mov	ax, LINEAR_SEL
	mov	ds, eax
	mov	es, eax
	mov	ss, eax
; WARNING: esp invalid here

;
; Enable the 64-bit page-translation-table entries by
; setting CR4.PAE=1 (this is _required_ before activating
; long mode). Paging is not enabled until after long mode
; is enabled.
;
	mov	eax, cr4
	or	al, 0x20
	mov	cr4, eax

;
; This is the Trapolean Page Tables that are guarenteed
;  under 4GB.
;
; Address Map:
;    10000 ~    12000 - efildr (loaded)
;    20000 ~    21000 - start64.com
;    21000 ~    22000 - efi64.com
;    22000 ~    90000 - efildr
;    90000 ~    96000 - 4G pagetable (will be reload later)
;
%ifdef GENPAGE
	mov	cr3, edx
%elifdef USE_LOW_EBDA
	mov	eax, 0x88000
	mov	cr3, eax
%else
	mov	eax, 0x90000
	mov	cr3, eax
%endif

;
; Enable long mode (set EFER.LME=1).
;
	mov	ecx, IA32_EFER
	rdmsr
	or	ax, 0x100
	wrmsr

;
; Enable Paging to activate long mode (set CR0.PG=1)
;
	mov	eax, cr0
	bts	eax, 31
	mov	cr0, eax

.JumpToLongMode:	equ $ + 1
	jmp	SYS_CODE64_SEL:.InLongMode
.InLongMode:

	bits 64

	mov	ax, SYS_DATA_SEL
	mov	ds, eax
	mov	es, eax
	mov	ss, eax
	lea	rsp, [REL MyStack]

;
; load IDT
;
	lidt	[REL idtr]

	jmp	BlockSignature + 2

%endif

	bits 16

%ifdef LEGACY_A20
Empty8042InputBuffer:
	xor	cx, cx
.Empty8042Loop:
	out	DELAY_PORT, ax		; Delay 1us
	in	al, KBD_STATUS_PORT	; Read the 8042 Status Port
	and	al, 2			; Check the Input Buffer Full Flag
	loopnz	.Empty8042Loop		; Loop until the input buffer is empty or a timout of 65536 uS
	ret
%endif

%ifdef GENPAGE
;
; Find place for page table and create it
;

EFILDR_BASE:		equ 0x2000	; Offset to start of EFILDR block
EFILDR_FILE_LENGTH	equ 8		; Dword in EFILDR_HEADER holding size of block
EBDA_SEG:		equ 0x40	; Segment:Offset for finding the EBDA
EBDA_OFFSET:		equ 0xE

CreatePageTable:
	mov	edx, [EFILDR_BASE + EFILDR_FILE_LENGTH]	; Size of EFILDR block -> EDX
	add	edx, EFILDR_BASE + 15			; Add base
	shr	edx, 4					; And round up to multiple of 16
	mov	ax, ds
	add	dx, ax					; Add in linear base
	add	dx, 255
	xor	dl, dl					; And round up to page size
; DX holds 16-bit segment of page table

	mov	cx, ds			; Save DS
	mov	ax, EBDA_SEG
	add	dh, 6			; Need 6 pages for table
	mov	ds, ax
	mov	ax, [EBDA_OFFSET]	; EBDA 16-bit segment now in AX
	mov	ds, cx			; Restore DS
	cmp	ax, dx			; Does page table fit under EBDA?
	jae	.continue		; Yes, continue
	jmp	PageTableError		; No, abort
.continue:
	sub	dh, 6			; Restore DX to start segment of page table
	mov	[PageTableSegment], dx	; Stash it for client
	push	es
	push	di			; Save ES:DI used to build page table

	mov	es, dx
	xor	di, di			; ES:DI points to start of page table
	inc	dh			; Bump DX to next page

;
; Set up page table root page (only 1 entry)
;
	xor	eax, eax
	mov	ax, dx
	inc	dh			; Bump DX to next page
	shl	eax, 4
	or	al, 3
	stosd
	xor	eax, eax
	mov	cx, 2046
	rep stosw			; Wipe rest of 1st page

;
; Set up page table 2nd page (depth 1 - 4 entries)
;
	mov	cx, 4
.loop1:
	mov	ax, dx
	inc	dh			; Bump DX to next page
	shl	eax, 4
	or	al, 3
	stosd
	xor	eax, eax
	stosd
	loop	.loop1
	mov	cx, 2032		; Wipe rest of 2nd page
	rep stosw

;
; Set up pages 3 - 6 (depth 2 - 2048 entries)
;
	xor	edx, edx		; Start at base of memory
	mov	dl, 0x83		; Flags at leaf nodes mark large pages (2MB each)
	mov	cx, 2048
.loop2:
	mov	eax, edx
	add	edx, 0x200000		; Bump EDX to next large page
	stosd
	xor	eax, eax
	stosd
	loop	.loop2

;
; Done - restore ES:DI and return
;
	pop	di
	pop	es
	ret

;
; Get here if not enough space between boot file
;   and bottom of the EBDA - print error and halt
;
PageTableError:
	add	sp, 2			; Clear return address of CreatePageTable
	mov	bx, 15
	mov	si, PageErrorMsg
.loop:
	lodsb
	test	al, al
	jz	.halt
	mov	ah, 14
	int	16
	jmp	.loop
.halt:
	hlt
	jmp .halt

	align 2, db 0

PageTableSegment:	dw 0
PageErrorMsg:		db 'Unable to Allocate Memory for Page Table', 0

%endif

;
; Data
;

	align 2, db 0

gdtr:
	dw GDT_END - GDT_BASE - 1
	dd GDT_BASE

;
; global descriptor table (GDT)
;

	align GDT_DESC_SIZE, db 0

GDT_BASE:
NULL_SEL:		equ $ - GDT_BASE
	times GDT_DESC_SIZE db 0
LINEAR_SEL:		equ $ - GDT_BASE
	GDT_DESC 0x92, 0xCF
LINEAR_CODE_SEL:	equ $ - GDT_BASE
	GDT_DESC 0x9A, 0xCF
SYS_DATA_SEL:		equ $ - GDT_BASE
	GDT_DESC 0x92, 0xCF
SYS_CODE_SEL:		equ $ - GDT_BASE
	GDT_DESC 0x9A, 0xCF
	times GDT_DESC_SIZE db 0
%ifdef X64
SYS_DATA64_SEL:		equ $ - GDT_BASE
	GDT_DESC 0x92, 0xCF
SYS_CODE64_SEL:		equ $ - GDT_BASE
	GDT_DESC 0x9A, 0xAF
%else
	times GDT_DESC_SIZE db 0
%endif
	times GDT_DESC_SIZE db 0
GDT_END:

	align 2, db 0

idtr:
	dw IDT_END - IDT_BASE - 1
	dd IDT_BASE
%ifdef X64
	dd 0
%endif

;
;  interrupt descriptor table (IDT)
;
;
;   Note: The hardware IRQ's specified in this table are the normal PC/AT IRQ
;       mappings.  This implementation only uses the system timer and all other
;	IRQs will remain masked.
;

	align IDT_DESC_SIZE, db 0

IDT_BASE:
%rep 20 ; Exceptions 0 - 19
	IDT_DESC
%endrep
	times 84 * IDT_DESC_SIZE db 0
%rep 16 ; Interrupts IRQ0 - IRQ15 mapped to vectors 0x68 - 0x77
	IDT_DESC
%endrep
	times IDT_DESC_SIZE db 0	; padding
IDT_END:

	align 4, db 0

MemoryMapSize:
	dd 0
MemoryMap:

	times SIZE_TO_STACK_16 - $ + $$ db 0

MyStack:
; below is the pieces of the IVT that is used to redirect INT 68h - 6fh
;    back to INT 08h - 0fh  when in real mode...  It is 'org'ed to a
;    known low address (20f00) so it can be set up by PlMapIrqToVect in
;    8259.c

%assign i 8
%rep 8
	int i
	iret
%assign	i i+1
%endrep

	times	0x1e - $ + MyStack db 0
BlockSignature: 
	dw 0xaa55
