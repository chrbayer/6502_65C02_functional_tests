;
; 6 5 C E 0 2   E X T E N D E D   O P C O D E S   T E S T
;
; Copyright (C) 2013-2017  Klaus Dormann
;
; This program is free software: you can redistribute it and/or modify
; it under the terms of the GNU General Public License as published by
; the Free Software Foundation, either version 3 of the License, or
; (at your option) any later version.
;
; This program is distributed in the hope that it will be useful,
; but WITHOUT ANY WARRANTY; without even the implied warranty of
; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
; GNU General Public License for more details.
;
; You should have received a copy of the GNU General Public License
; along with this program.  If not, see <http://www.gnu.org/licenses/>.


; This program is designed to test all additional 65C02 opcodes, addressing
; modes and functionality not available in the NMOS version of the 6502.
; The 6502_functional_test is a prerequisite to this test.
; NMI, IRQ, STP & WAI are covered in the 6502_interrupt_test.
;
; version 04-dec-2017
; contact info at http://2m5.de or email K@2m5.de
;
; assembled with AS65 from http://www.kingswood-consulting.co.uk/assemblers/
; command line switches: -l -m -s2 -w -x -h0
;                         |  |  |   |  |  no page headers in listing
;                         |  |  |   |  65C02 extensions
;                         |  |  |   wide listing (133 char/col)
;                         |  |  write intel hex file instead of binary
;                         |  expand macros in listing
;                         generate pass2 listing
;
; No IO - should be run from a monitor with access to registers.
; To run load intel hex image with a load command, than alter PC to 400 hex
; (code_segment) and enter a go command.
; Loop on program counter determines error or successful completion of test.
; Check listing for relevant traps (jump/branch *).
; Please note that in early tests some instructions will have to be used before
; they are actually tested!
;
; RESET, NMI or IRQ should not occur and will be trapped if vectors are enabled.
; Tests documented behavior of the original 65C02 only!
; Decimal ops will only be tested with valid BCD operands and the V flag will
; be ignored as it is absolutely useless in decimal mode.
;
; Debugging hints:
;     Most of the code is written sequentially. if you hit a trap, check the
;   immediately preceeding code for the instruction to be tested. Results are
;   tested first, flags are checked second by pushing them onto the stack and
;   pulling them to the accumulator after the result was checked. The "real"
;   flags are no longer valid for the tested instruction at this time!
;     If the tested instruction was indexed, the relevant index (X or Y) must
;   also be checked. Opposed to the flags, X and Y registers are still valid.
;
; versions:
;   19-jul-2013  1st version distributed for testing
;   23-jul-2013  fixed BRA out of range due to larger trap macros
;                added RAM integrity check
;   16-aug-2013  added error report to standard output option
;   23-aug-2015  change revoked
;   24-aug-2015  all self modifying immediate opcodes now execute in data RAM
;   28-aug-2015  fixed decimal adc/sbc immediate only testing carry
;   09-feb-2017  fixed RMB/SMB tested when they shouldn't be tested
;   04-dec-2017  fixed BRK not tested for actually going through the IRQ vector
;                added option to skip the remainder of a failing test
;                in report.i65
;                added skip override to undefined opcode as NOP test


; C O N F I G U R A T I O N

;ROM_vectors writable (0=no, 1=yes)
;if ROM vectors can not be used interrupts will not be trapped
;as a consequence BRK can not be tested but will be emulated to test RTI
ROM_vectors = 0

;load_data_direct (0=move from code segment, 1=load directly)
;loading directly is preferred but may not be supported by your platform
;0 produces only consecutive object code, 1 is not suitable for a binary image
load_data_direct = 0

;I_flag behavior (0=force enabled, 1=force disabled, 2=prohibit change, 3=allow
;change) 2 requires extra code and is not recommended.
I_flag = 3

;configure memory - try to stay away from memory used by the system
;zero_page memory start address, $4e (78) consecutive Bytes required
;                                add 2 if I_flag = 2
zero_page = $a

;data_segment memory start address, $63 (99) consecutive Bytes required
; + 12 Bytes at data_segment + $f9 (JMP indirect page cross test)
data_segment = $200
    .if (data_segment & $ff) != 0
        ERROR ERROR ERROR low byte of data_segment MUST be $00 !!
    .endif

;code_segment memory start address, 10kB of consecutive space required
;                                   add 1 kB if I_flag = 2
code_segment = $c000

;added WDC only opcodes WAI & STP (0=test as NOPs, >0=no test)
wdc_op = 1

;added Rockwell & WDC opcodes BBR, BBS, RMB & SMB
;(0=test as NOPs, 1=full test, >1=no test)
rkwl_wdc_op = 1

;skip testing all undefined opcodes override
;0=test as NOP, >0=skip
skip_nop = 0

;report errors through I/O channel (0=use standard self trap loops, 1=include
;report.i65 as I/O channel, add 3 kB)
report = 0

;RAM integrity test option. Checks for undesired RAM writes.
;set lowest non RAM or RAM mirror address page (-1=disable, 0=64k, $40=16k)
;leave disabled if a monitor, OS or background interrupt is allowed to alter RAM
ram_top = $10


.cpu "65ce02"

;macros for error & success traps to allow user modification
;example:
;trap    .macro
;        jsr my_error_handler
;        .endmacro
;trap_eq .macro
;        bne skip
;        trap           ;failed equal (zero)
;skip
;        .endmacro
;
; my_error_handler should pop the calling address from the stack and report it.
; putting larger portions of code (more than 3 bytes) inside the trap macro
; may lead to branch range problems for some tests.
    .if report == 0
trap    .macro
        jmp *           ;failed anyway
        .endmacro
trap_eq .macro
        beq *           ;failed equal (zero)
        .endmacro
trap_ne .macro
        bne *           ;failed not equal (non zero)
        .endmacro
trap_cs .macro
        bcs *           ;failed carry set
        .endmacro
trap_cc .macro
        bcc *           ;failed carry clear
        .endmacro
trap_mi .macro
        bmi *           ;failed minus (bit 7 set)
        .endmacro
trap_pl .macro
        bpl *           ;failed plus (bit 7 clear)
        .endmacro
trap_vs .macro
        bvs *           ;failed overflow set
        .endmacro
trap_vc .macro
        bvc *           ;failed overflow clear
        .endmacro
; please observe that during the test the stack gets invalidated
; therefore a RTS inside the success macro is not possible
success .macro
        jmp *           ;test passed, no errors
        .endmacro
    .endif
    .if report == 1
trap    .macro
        jsr report_error
        .endmacro
trap_eq .macro
        bne skip
        trap           ;failed equal (zero)
skip
        .endmacro
trap_ne .macro
        beq skip
        trap            ;failed not equal (non zero)
skip
        .endmacro
trap_cs .macro
        bcc skip
        trap            ;failed carry set
skip
        .endmacro
trap_cc .macro
        bcs skip
        trap            ;failed carry clear
skip
        .endmacro
trap_mi .macro
        bpl skip
        trap            ;failed minus (bit 7 set)
skip
        .endmacro
trap_pl .macro
        bmi skip
        trap            ;failed plus (bit 7 clear)
skip
        .endmacro
trap_vs .macro
        bvc skip
        trap            ;failed overflow set
skip
        .endmacro
trap_vc .macro
        bvs skip
        trap            ;failed overflow clear
skip
        .endmacro
; please observe that during the test the stack gets invalidated
; therefore a RTS inside the success macro is not possible
success .macro
        jsr report_success
        .endmacro
    .endif


carry   = %00000001   ;flag bits in status
zero    = %00000010
intdis  = %00000100
decmode = %00001000
break   = %00010000
reserv  = %00100000
overfl  = %01000000
minus   = %10000000

fc      = carry
fz      = zero
fzc     = carry+zero
fv      = overfl
fvz     = overfl+zero
fn      = minus
fnc     = minus+carry
fnz     = minus+zero
fnzc    = minus+zero+carry
fnv     = minus+overfl

fao     = break+reserv    ;bits always on after PHP, BRK
fai     = fao+intdis      ;+ forced interrupt disable
m8      = $ff             ;8 bit mask
m8i     = $ff&~intdis     ;8 bit mask - interrupt disable

;macros to allow masking of status bits.
;masking of interrupt enable/disable on load and compare
;masking of always on bits after PHP or BRK (unused & break) on compare
        .if I_flag == 0
load_flag   .macro
            lda #\1&m8i         ;force enable interrupts (mask I)
            .endmacro
cmp_flag    .macro
            cmp #(\1|fao)&m8i   ;I_flag is always enabled + always on bits
            .endmacro
eor_flag    .macro
            eor #(\1&m8i|fao)   ;mask I, invert expected flags + always on bits
            .endmacro
        .endif
        .if I_flag == 1
load_flag   .macro
            lda #\1|intdis      ;force disable interrupts
            .endmacro
cmp_flag    .macro
            cmp #(\1|fai)&m8    ;I_flag is always disabled + always on bits
            .endmacro
eor_flag    .macro
            eor #(\1|fai)       ;invert expected flags + always on bits + I
            .endmacro
        .endif
        .if I_flag == 2
load_flag   .macro
            lda #\1
            ora flag_I_on       ;restore I-flag
            and flag_I_off
            .endmacro
cmp_flag    .macro
            eor flag_I_on       ;I_flag is never changed
            cmp #(\1|fao)&m8i   ;expected flags + always on bits, mask I
            .endmacro
eor_flag    .macro
            eor flag_I_on       ;I_flag is never changed
            eor #(\1&m8i|fao)   ;mask I, invert expected flags + always on bits
            .endmacro
        .endif
        .if I_flag == 3
load_flag   .macro
            lda #\1             ;allow test to change I-flag (no mask)
            .endmacro
cmp_flag    .macro
            cmp #(\1|fao)&m8    ;expected flags + always on bits
            .endmacro
eor_flag    .macro
            eor #\1|fao         ;invert expected flags + always on bits
            .endmacro
        .endif

;macros to set (register|memory|zeropage) & status
set_stat    .macro       ;setting flags in the processor status register
            load_flag \1
            pha         ;use stack to load status
            plp
            .endmacro

set_a       .macro       ;precharging accu & status
            load_flag \2
            pha         ;use stack to load status
            lda #<\1     ;precharge accu
            plp
            .endmacro

set_x       .macro       ;precharging index & status
            load_flag \2
            pha         ;use stack to load status
            ldx #<\1     ;precharge index x
            plp
            .endmacro

set_y       .macro       ;precharging index & status
            load_flag \2
            pha         ;use stack to load status
            ldy #<\1     ;precharge index y
            plp
            .endmacro

set_z       .macro       ;precharging index & status
            load_flag \2
            pha         ;use stack to load status
            ldz #<\1     ;precharge index x
            plp
            .endmacro

set_ax      .macro       ;precharging indexed accu & immediate status
            load_flag \2
            pha         ;use stack to load status
            lda \1,x    ;precharge accu
            plp
            .endmacro

set_ay      .macro       ;precharging indexed accu & immediate status
            load_flag \2
            pha         ;use stack to load status
            lda \1,y    ;precharge accu
            plp
            .endmacro

set_zp      .macro       ;precharging indexed zp & immediate status
            load_flag \2
            pha         ;use stack to load status
            lda \1,x    ;load to zeropage
            sta zpt
            plp
            .endmacro

set_zx      .macro       ;precharging zp,x & immediate status
            load_flag \2
            pha         ;use stack to load status
            lda \1,x    ;load to indexed zeropage
            sta zpt,x
            plp
            .endmacro

set_abs     .macro       ;precharging indexed memory & immediate status
            load_flag \2
            pha         ;use stack to load status
            lda \1,x    ;load to memory
            sta abst
            plp
            .endmacro

set_absx    .macro       ;precharging abs,x & immediate status
            load_flag \2
            pha         ;use stack to load status
            lda \1,x    ;load to indexed memory
            sta abst,x
            plp
            .endmacro

;macros to test (register|memory|zeropage) & status & (mask)
tst_stat    .macro       ;testing flags in the processor status register
            php         ;save status
            pla         ;use stack to retrieve status
            pha
            cmp_flag \1
            trap_ne
            plp         ;restore status
            .endmacro

tst_a       .macro       ;testing result in accu & flags
            php         ;save flags
            cmp #<\1     ;test result
            trap_ne
            pla         ;load status
            pha
            cmp_flag \2
            trap_ne
            plp         ;restore status
            .endmacro

tst_as      .macro       ;testing result in accu & flags, save accu
            pha
            php         ;save flags
            cmp #<\1     ;test result
            trap_ne
            pla         ;load status
            pha
            cmp_flag \2
            trap_ne
            plp         ;restore status
            pla
            .endmacro

tst_x       .macro       ;testing result in x index & flags
            php         ;save flags
            cpx #<\1     ;test result
            trap_ne
            pla         ;load status
            pha
            cmp_flag \2
            trap_ne
            plp         ;restore status
            .endmacro

tst_y       .macro       ;testing result in y index & flags
            php         ;save flags
            cpy #<\1     ;test result
            trap_ne
            pla         ;load status
            pha
            cmp_flag \2
            trap_ne
            plp         ;restore status
            .endmacro

tst_z       .macro       ;testing result in z index & flags
            php         ;save flags
            cpz #<\1     ;test result
            trap_ne
            pla         ;load status
            pha
            cmp_flag \2
            trap_ne
            plp         ;restore status
            .endmacro

tst_ax      .macro       ;indexed testing result in accu & flags
            php         ;save flags
            cmp \1,x    ;test result
            trap_ne
            pla         ;load status
            eor_flag \3
            cmp \2,x    ;test flags
            trap_ne     ;
            .endmacro

tst_ay      .macro       ;indexed testing result in accu & flags
            php         ;save flags
            cmp \1,y    ;test result
            trap_ne     ;
            pla         ;load status
            eor_flag \3
            cmp \2,y    ;test flags
            trap_ne
            .endmacro

tst_zp      .macro       ;indexed testing result in zp & flags
            php         ;save flags
            lda zpt
            cmp \1,x    ;test result
            trap_ne
            pla         ;load status
            eor_flag \3
            cmp \2,x    ;test flags
            trap_ne
            .endmacro

tst_zx      .macro       ;testing result in zp,x & flags
            php         ;save flags
            lda zpt,x
            cmp \1,x    ;test result
            trap_ne
            pla         ;load status
            eor_flag \3
            cmp \2,x    ;test flags
            trap_ne
            .endmacro

tst_abs     .macro       ;indexed testing result in memory & flags
            php         ;save flags
            lda abst
            cmp \1,x    ;test result
            trap_ne
            pla         ;load status
            eor_flag \3
            cmp \2,x    ;test flags
            trap_ne
            .endmacro

tst_absx    .macro       ;testing result in abs,x & flags
            php         ;save flags
            lda abst,x
            cmp \1,x    ;test result
            trap_ne
            pla         ;load status
            eor_flag \3
            cmp \2,x    ;test flags
            trap_ne
            .endmacro

; RAM integrity test
;   verifies that none of the previous tests has altered RAM outside of the
;   designated write areas.
;   uses zpt word as indirect pointer, zpt+2 word as checksum
        .if ram_top > -1
check_ram   .macro
            cld
            lda #0
            sta zpt         ;set low byte of indirect pointer
            sta zpt+3       ;checksum high byte
            clc
            ldx #zp_bss-zero_page ;zeropage - write test area
ccs3        adc zero_page,x
            bcc ccs2
            inc zpt+3       ;carry to high byte
            clc
ccs2        inx
            bne ccs3
            ldx #>(abs1)    ;set high byte of indirect pointer
            stx zpt+1
            ldy #<(abs1)    ;data after write & execute test area
ccs5        adc (zpt),y
            bcc ccs4
            inc zpt+3       ;carry to high byte
            clc
ccs4        iny
            bne ccs5
            inx             ;advance RAM high address
            stx zpt+1
            cpx #ram_top
            bne ccs5
            sta zpt+2       ;checksum low is
            cmp ram_chksm   ;checksum low expected
            trap_ne         ;checksum mismatch
            lda zpt+3       ;checksum high is
            cmp ram_chksm+1 ;checksum high expected
            trap_ne         ;checksum mismatch
            .endmacro
        .else
check_ram   .macro
            ;RAM check disabled - RAM size not set
            .endmacro
        .endif

test_num    .var 0
next_test   .segment        ;make sure, tests don't jump the fence
            lda test_case   ;previous test
            cmp #test_num
            trap_ne         ;test is out of sequence
test_num    .var test_num + 1
            lda #test_num   ;*** next tests' number
            sta test_case
            check_ram       ;uncomment to find altered RAM after each test
            .endsegment
next_test_   .segment       ;make sure, tests don't jump the fence
            lda test_case   ;previous test
            cmp #test_num
            trap_ne         ;test is out of sequence
test_num    .var test_num + 1
            lda #test_num   ;*** next tests' number
            sta test_case
            ;check_ram       ;uncomment to find altered RAM after each test
            .endsegment

bss        .segment
;break test interrupt save
irq_a   .byte 0                ;a register
irq_x   .byte 0                ;x register
    .if I_flag == 2
;masking for I bit in status
flag_I_on   .byte 0            ;or mask to load flags
flag_I_off  .byte 0            ;and mask to load flags
    .endif
zpt                            ;5 bytes store/modify test area
;add/subtract operand generation and result/flag prediction
adfc    .byte 0                ;carry flag before op
ad1     .byte 0                ;operand 1 - accumulator
ad2     .byte 0                ;operand 2 - memory / immediate
adrl    .byte 0                ;expected result bits 0-7
adrh    .byte 0                ;expected result bit 8 (carry)
adrf    .byte 0                ;expected flags NV0000ZC (-V in decimal mode)
sb2     .byte 0                ;operand 2 complemented for subtract
zp_bss
zp1     .byte  $c3,$82,$41,0   ;test patterns for LDx BIT ROL ROR ASL LSR
zp7f    .byte  $7f             ;test pattern for compare
;logical zeropage operands
zpOR    .byte  0,$1f,$71,$80   ;test pattern for OR
zpAN    .byte  $0f,$ff,$7f,$80 ;test pattern for AND
zpEO    .byte  $ff,$0f,$8f,$8f ;test pattern for EOR
;indirect addressing pointers
ind1    .word  abs1            ;indirect pointer to pattern in absolute memory
        .word  abs1+1
        .word  abs1+2
        .word  abs1+3
        .word  abs7f
inw1    .word  abs1-$f8        ;indirect pointer for wrap-test pattern
indt    .word  abst            ;indirect pointer to store area in absolute memory
        .word  abst+1
        .word  abst+2
        .word  abst+3
inwt    .word  abst-$f8        ;indirect pointer for wrap-test store
indAN   .word  absAN           ;indirect pointer to AND pattern in absolute memory
        .word  absAN+1
        .word  absAN+2
        .word  absAN+3
indEO   .word  absEO           ;indirect pointer to EOR pattern in absolute memory
        .word  absEO+1
        .word  absEO+2
        .word  absEO+3
indOR   .word  absOR           ;indirect pointer to OR pattern in absolute memory
        .word  absOR+1
        .word  absOR+2
        .word  absOR+3
;add/subtract indirect pointers
adi2    .word  ada2            ;indirect pointer to operand 2 in absolute memory
sbi2    .word  sba2            ;indirect pointer to complemented operand 2 (SBC)
adiy2   .word  ada2-$ff        ;with offset for indirect indexed
sbiy2   .word  sba2-$ff
zp_bss_end
        .endsegment

data    .segment
pg_x    .byte  0,0             ;high JMP indirect address for page cross bug
test_case   .byte  0           ;current test number
ram_chksm   .byte  0,0         ;checksum for RAM integrity test
;add/subtract operand copy - abs tests write area
abst                           ;5 bytes store/modify test area
ada2    .byte  0               ;operand 2
sba2    .byte  0               ;operand 2 complemented for subtract
        .byte  0,0,0           ;fill remaining bytes
data_bss
    .if load_data_direct = 1
ex_adci adc #0                 ;execute immediate opcodes
        rts
ex_sbci sbc #0                 ;execute immediate opcodes
        rts
    .else
ex_adci .byte  0,0,0
ex_sbci .byte  0,0,0
    .endif
abs1    .byte  $c3,$82,$41,0   ;test patterns for LDx BIT ROL ROR ASL LSR
abs7f   .byte  $7f             ;test pattern for compare
;loads
fLDx    .byte  fn,fn,0,fz      ;expected flags for load
;shifts
rASL                           ;expected result ASL & ROL -carry
rROL    .byte  $86,$04,$82,0   ; "
rROLc   .byte  $87,$05,$83,1   ;expected result ROL +carry
rLSR                           ;expected result LSR & ROR -carry
rROR    .byte  $61,$41,$20,0   ; "
rRORc   .byte  $e1,$c1,$a0,$80 ;expected result ROR +carry
fASL                           ;expected flags for shifts
fROL    .byte  fnc,fc,fn,fz    ;no carry in
fROLc   .byte  fnc,fc,fn,0     ;carry in
fLSR
fROR    .byte  fc,0,fc,fz      ;no carry in
fRORc   .byte  fnc,fn,fnc,fn   ;carry in
;increments (decrements)
rINC    .byte  $7f,$80,$ff,0,1 ;expected result for INC/DEC
fINC    .byte  0,fn,fn,fz,0    ;expected flags for INC/DEC
;logical memory operand
absOR   .byte  0,$1f,$71,$80   ;test pattern for OR
absAN   .byte  $0f,$ff,$7f,$80 ;test pattern for AND
absEO   .byte  $ff,$0f,$8f,$8f ;test pattern for EOR
;logical accu operand
absORa  .byte  0,$f1,$1f,0     ;test pattern for OR
absANa  .byte  $f0,$ff,$ff,$ff ;test pattern for AND
absEOa  .byte  $ff,$f0,$f0,$0f ;test pattern for EOR
;logical results
absrlo  .byte  0,$ff,$7f,$80
absflo  .byte  fz,fn,0,fn
data_bss_end
;define area for page crossing JMP (abs) & JMP (abs,x) test
jxi_tab = data_segment + $100 - 7     ;JMP (jxi_tab,x) x=6
ji_tab  = data_segment + $100 - 3     ;JMP (ji_tab+2)
jxp_tab = data_segment + $100         ;JMP (jxp_tab-255) x=255
        .endsegment


*       = zero_page
        .dsection bss
        bss

*       = data_segment
        .dsection data
        data

code    .segment
start   cld
        ldx #$ff
        txs
        lda #0          ;*** test 0 = initialize
        sta test_case

;stop interrupts before initializing BSS
    .if I_flag == 1
        sei
    .endif

;initialize I/O for report channel
    .if report == 1
        jsr report_init
    .endif

;initialize BSS segment
    .if load_data_direct != 1
        ldx #zp_end-zp_init-1
ld_zp   lda zp_init,x
        sta zp_bss,x
        dex
        bpl ld_zp
        ldx #data_end-data_init-1
ld_data lda data_init,x
        sta data_bss,x
        dex
        bpl ld_data
      .if ROM_vectors == 1
        ldx #5
ld_vect lda vec_init,x
        sta vec_bss,x
        dex
        bpl ld_vect
      .endif
    .endif

;retain status of interrupt flag
    .if I_flag == 2
        php
        pla
        and #4          ;isolate flag
        sta flag_I_on   ;or mask
        eor #<(~4)     ;reverse
        sta flag_I_off  ;and mask
    .endif

;generate checksum for RAM integrity test
    .if ram_top > -1
        lda #0
        sta zpt         ;set low byte of indirect pointer
        sta ram_chksm+1 ;checksum high byte
        ldx #11         ;reset modifiable RAM
gcs1    sta jxi_tab,x   ;JMP indirect page cross area
        dex
        bpl gcs1
        clc
        ldx #zp_bss-zero_page ;zeropage - write test area
gcs3    adc zero_page,x
        bcc gcs2
        inc ram_chksm+1 ;carry to high byte
        clc
gcs2    inx
        bne gcs3
        ldx #>(abs1)   ;set high byte of indirect pointer
        stx zpt+1
        ldy #<(abs1)   ;data after write & execute test area
gcs5    adc (zpt),y
        bcc gcs4
        inc ram_chksm+1 ;carry to high byte
        clc
gcs4    iny
        bne gcs5
        inx             ;advance RAM high address
        stx zpt+1
        cpx #ram_top
        bne gcs5
        sta ram_chksm   ;checksum complete
    .endif
        next_test

; quick/dirty test 16-bit branches by jumping across Z register test code (which should be more than 128 bytes large).

        ldy #0
        bra braf0       ; branch should always be taken
        trap

        dey
        dey
brab0   dey             ; We should land here, or Y test will fail
        dey
        dey
        cpy #0
        trap_ne

        ; Check one conditional branch
        beq beqf0
        trap

        dey
        dey
beqb0   dey             ; We should land here, or Y test will fail
        dey
        dey
        cpy #0
        trap_ne

        ; 16-bit BSR test
        ldy #0
        bsr bsrf0
        dey
        dey
        dey
        cpy #0
        trap_ne

        next_test

; Basic Z register tests.  Verify that Z can be changed and basic comparisons work.

        ; test STZ zp gives #$aa
        ldz #$aa
        cpz #$aa        ; verify load/compare immediate is ok
        trap_ne

        lda #$55
        sta zpt
        stz zpt         ; overwrite it
        lda zpt         ; we should get $aa
        cmp #$aa
        trap_ne
        cpz zpt         ; check of  CPZ zp
        trap_ne

        ; test STZ abs gives #$aa
        lda #$55
        sta abst
        stz abst        ; overwrite it
        lda abst        ; we should get $aa
        cmp #$aa
        trap_ne
        cpz abst        ; check of CPZ abs

        ; test STZ zp,x works
        lda #1
        tax
        sta zpt+0
        sta zpt+1
        sta zpt+2
        stz zpt,x
        lda zpt+1
        cmp #$aa
        trap_ne

        ; test STZ abs,x works
        sta abst+0
        sta abst+1
        sta abst+2
        stz abst,x
        lda abst+1
        cmp #$aa

        cpz #$aa        ; verify that Z contains #$aa
        trap_ne

        ; Clear memory
        ldz #$0
        stz zpt+0
        stz zpt+1
        stz zpt+2
        stz abst+0
        sta abst+1
        sta abst+2

        ; Quick tests for TAZ / TZA (flags not yet checked)

        lda #$99
        taz
        cpz #$99
        trap_ne

        ldz #$44
        tza
        cmp #$44
        trap_ne

;testing stack operations PHZ PLZ
        lda #$99        ;protect a
        ldx #$ff        ;initialize stack
        txs
        ldz #$55
        phz
        ldz #$aa
        phz
        cpz $1fe        ;on stack ?
        trap_ne
        tsx
        cpx #$fd        ;sp decremented?
        trap_ne
        plz
        cpz #$aa        ;successful retreived from stack?
        trap_ne
        plz
        cpz #$55
        trap_ne
        cpz $1ff        ;remains on stack?
        trap_ne
        tsx
        cpx #$ff        ;sp incremented?
        trap_ne
        cmp #$99        ;unchanged?
        trap_ne

; test PHZ does not alter flags or Z but PLZ does
        ldx #$55        ;protect x
        ldy #$aa        ;protect y
        set_z 1,$ff     ;push
        phz
        tst_z 1,$ff
        set_z 0,0
        phz
        tst_z 0,0
        set_z $ff,$ff
        phz
        tst_z $ff,$ff
        set_z 1,0
        phz
        tst_z 1,0
        set_z 0,$ff
        phz
        tst_z 0,$ff
        set_z $ff,0
        phz
        tst_z $ff,0
        set_z 0,$ff     ;pull
        plz
        tst_z $ff,$ff-zero
        set_z $ff,0
        plz
        tst_z 0,zero
        set_z $fe,$ff
        plz
        tst_z 1,$ff-zero-minus
        set_z 0,0
        plz
        tst_z $ff,minus
        set_z $ff,$ff
        plz
        tst_z 0,$ff-minus
        set_z $fe,0
        plz
        tst_z 1,0
        cpy #$aa        ;Y unchanged
        cpx #$55        ;X unchanged
        trap_ne

; Quick check that (zp) is now really (zp),z
        lda #$55        ; set up test area
        sta ada2

        ldz #$ff        ; set up indirect offset
        lda (adiy2),z   ; load value
        cmp #$55        ; compare to expected
        trap_ne

        ldz #0          ; Restore Z to default of 0

        next_test

; branch around 16-bit branch landing area
        bra stacktests

; Landing area for forward 16-bit branches.

        iny
        iny
braf0   iny             ; We should land here
        iny
        iny
        cpy #$03
        trap_ne

        beq   brab0     ; Now branch back...

        iny
        iny
beqf0   iny             ; We should land here
        iny
        iny
        cpy #$03
        trap_ne

        beq   beqb0     ; Now branch back...

        iny
        iny
bsrf0   iny
        iny
        iny
        cpy #$03
        trap_ne
        rts

rtnimm  rtn #2

stacktests

; Test phw variants
        phw #$aa55      ; Should push $aa then $55
        pla
        cmp #$55
        trap_ne
        pla
        cmp #$aa
        trap_ne

        phw abs1
        pla
        cmp abs1+0
        trap_ne
        pla
        cmp abs1+1
        trap_ne

; Test rtn #imm
        phw #$aa55
        jsr rtnimm
        tsx
        cpx #$ff        ; stack should be back here now
        trap_ne

; Extended stack mode - Verify TYS lets us move stack to new page

        ldy #$ff        ; set Y to different value
        tsy
        cpy #$01        ; This should now be #$01 by default
        trap_ne
        iny             ; move stack up a page (to #$02)
        ldx #$ff
        tys
        txs             ; init stack to $02ff

        ldx $2ff        ; backup memory content in X and Y
        ldy $2fe

        ; zero stack area
        lda #$00
        sta $2ff
        sta $2fe
        tya

        ldy #$55
        phy
        cpy $2ff        ; on stack?
        trap_ne
        ldy #$aa
        phy
        cpy $2fe        ; on stack?
        trap_ne
        ldy #$99
        ply
        cpy #$aa        ; got back ok?
        trap_ne
        ply
        cpy #$55        ; got back ok?
        trap_ne

        tsy
        cpy #$02        ; got back stack upper byte?
        trap_ne

        sta $2fe        ; restore memory content
        stx $2ff

; Extended stack mode - Verify that with E bit set (the default) that the stack
;                       still wraps at both ends.

        ldy #$01        ; set up stack again
        ldx #$ff
        tys
        txs

        php
        pla
        and #$20        ; verify that 'E' (previously reserved) reads back 1
        trap_eq

        lda #$00        ; force processor status to 0...
        pha
        plp
        php
        pla
        and #$20        ; verify that 'E' (previously reserved) still reads back 1
        trap_eq

        cle
        php
        pla
        and #$20        ; verify that 'E' (previously reserved) now reads back 0
        trap_ne

        plx             ; pop bogus value off the stack (should wrap from $01ff to $0200)
        tsy
        tsx
        cpy #$02        ; verify stack wrapped
        trap_ne
        cpx #$00
        trap_ne

        lda #$00
        sta $200
        lda #$99
        pha
        cmp $200        ; stack written as expected?
        trap_ne

        tsy
        tsx
        cpy #$01        ; verify stack wrapped
        trap_ne
        cpx #$ff
        trap_ne

        lda #$ff
        pha
        plp
        pla
        and #$20        ; verify that 'E' (previously reserved) still reads back 0
        trap_ne

        see             ; re-set stack extend disable bit

        php
        pla
        and #$20        ; verify that 'E' (previously reserved) reads back 1 again
        trap_eq

        ldy #$01        ; restore stack setup
        ldx #$ff
        tys
        txs

        next_test

; Base page register test - Verify TAB/TBA can save/restore as expected and that at least one
; zero page based addressing mode is affected by moving zero page around.

        tba
        trap_ne         ; This should give us back zero

        lda #$03
        tab
        lda #$99        ; Trash A
        tba
        cmp #$03        ; make sure it's as expected again
        trap_ne

        ; quick zero page write test
        ldy zpt+$300    ; backup old value
        lda #$55
        sta zpt+$300    ; trash test location

        lda #$99
        sta zpt         ; store to 'zero page' location
        cmp zpt+$300    ; verify it landed in expected place
        trap_ne

        sty zpt+$300    ; restore old value
        lda #$00
        tab             ; put zero page back

        next_test

; Quick smoke check of NEG.
        lda #$00
        neg
        trap_ne
        trap_mi
        cmp #$00
        trap_ne
        lda #$01
        neg
        trap_eq
        trap_pl
        cmp #$ff
        trap_ne
        lda #$80
        neg
        trap_pl
        trap_eq
        cmp #$80
        trap_ne

        next_test

; Quick sanity test of ASR
        lda #$7f
        sec           ; set carry bit
        asr           ; arithmetic shift right shouldn't bring in carry bit
        trap_cc       ; carry should be shifted out
        cmp #$3f      ; top bit should have remained zero
        trap_ne
        lda #$80
        asr
        trap_cs
        cmp #$c0
        trap_ne
        asr           ; $e0
        asr           ; $f0
        trap_cs
        cmp #$f0
        trap_ne
        asr
        asr
        asr
        asr
        trap_cs
        cmp #$ff
        trap_ne
        asr
        trap_cc

; Do the same for ASR zp and ASR zp,x
        lda #$7f
        sta zpt
        sec
        asr zpt
        trap_cc
        lda zpt
        cmp #$3f
        trap_ne

        lda #$80
        ldx #$1
        sta zpt,x
        sec
        asr zpt,x
        trap_cs
        lda zpt,x
        cmp #$c0
        trap_ne

        next_test

; test ASW abs (this is a shift left)
        lda #$80
        sta abst+0
        lda #$00
        sta abst+1
        sec
        asw abst    ; should not shift in carry
        trap_eq     ; result should not be zero ($0100)
        trap_cs     ; carry out should be zero
        lda abst+0
        trap_ne     ; should be zero
        lda abst+1
        trap_eq     ; shouldn't be zero
        cmp #$01
        trap_ne

        ; Check that zero flag is not set if upper byte is zero, nor is
        ; negative flag set if lower byte winds up with high bit set

        lda #$40
        sta abst+0
        lda #$00
        sta abst+1
        sec
        asw abst
        trap_eq     ; should not be zero
        trap_mi     ; should not be minus

        ; Check that zero flag is set properly if both bytes wind up zero
        lda #$00
        sta abst+0
        lda #$80
        sta abst+1
        sec
        asw abst
        trap_ne     ; result should be zero
        trap_cc     ; carry should be set

; test ROW abs (this is a shift left)
        lda #$80
        sta abst+0
        lda #$00
        sta abst+1
        sec
        row abst    ; should not shift in carry
        trap_eq     ; result should not be zero ($0100)
        trap_cs     ; carry out should be zero
        lda abst+0
        cmp #$01    ; verify carry shifted in
        trap_ne     ;
        lda abst+1
        trap_eq     ; shouldn't be zero
        cmp #$01
        trap_ne

        ; Check that zero flag is not set if upper byte is zero, nor is
        ; negative flag set if lower byte winds up with high bit set

        lda #$40
        sta abst+0
        lda #$00
        sta abst+1
        sec
        row abst
        trap_eq     ; should not be zero
        trap_mi     ; should not be minus

        ; Check that zero flag is set properly if both bytes wind up zero
        lda #$00
        sta abst+0
        lda #$80
        sta abst+1
        clc
        row abst
        trap_ne     ; result should be zero
        trap_cc     ; carry should be set

        next_test

; Quick test of sty abs,x and stx abs,y
        ldx #$01
        ldy #$fc
        lda #$01
        sty abst,x
        cpy abst+1
        trap_ne

        ldx #$cf
        ldy #$01
        stx abst,y
        cpx abst+1
        trap_ne

        next_test

; Quick test of ldz abs and ldz abs,x
        lda #$bb
        sta abst
        ldz abst
        cpz #$bb
        trap_ne

        ldx #$01
        ldz abst,x
        cpz #$cf
        trap_ne

        next_test

; Test stack indirect indexed
        lda ind1+3
        pha
        lda ind1+2
        pha
        lda ind1+1
        pha
        lda ind1+0
        pha
        ldy #1
        lda (#$3,s),y     ; shoud load from 2nd stack word (abs1+1) and add 1, so abs1+2
        cmp abs1+2
        trap_ne

        lda indt+5
        pha
        lda indt+4        ; this will point at indt+2
        pha
        lda indt+1
        pha
        lda indt+0
        pha
        lda #$44
        sta (#$3,s),y
        cmp abst+3        ; should have landed here
        trap_ne

        ldx #$ff          ; reset stack
        txs

        next_test

; testing Z increment/decrement INZ & DEZ

        ldx #$ac    ;protect x & y
        ldy #$dc
        set_z $fe,$ff
        inz             ;ff
        tst_z $ff,$ff-zero
        inz            ;00
        tst_z 0,$ff-minus
        inz            ;01
        tst_z 1,$ff-minus-zero
        dez            ;00
        tst_z 0,$ff-minus
        dez            ;ff
        tst_z $ff,$ff-zero
        dez            ;fe
        set_z $fe,0
        inz            ;ff
        tst_z $ff,minus
        inz            ;00
        tst_z 0,zero
        inz            ;01
        tst_z 1,0
        dez            ;00
        tst_z 0,zero
        dez            ;ff
        tst_z $ff,minus
        cpx #$ac
        trap_ne     ;x altered during test
        cpy #$dc
        trap_ne     ;y altered during test
        tsx
        cpx #$ff
        trap_ne     ;sp push/pop mismatch

        ldz #$00    ; restore default Z value for next test.

        next_test

; testing load / store accumulator LDA / STA (zp)
        ldx #$99    ;protect x & y
        ldy #$66
        set_stat 0
        lda (ind1),z
        php         ;test stores do not alter flags
        eor #$c3
        plp
        sta (indt),z
        php         ;flags after load/store sequence
        eor #$c3
        cmp #$c3    ;test result
        trap_ne
        pla         ;load status
        eor_flag 0
        cmp fLDx    ;test flags
        trap_ne
        set_stat 0
        lda (ind1+2),z
        php         ;test stores do not alter flags
        eor #$c3
        plp
        sta (indt+2),z
        php         ;flags after load/store sequence
        eor #$c3
        cmp #$82    ;test result
        trap_ne
        pla         ;load status
        eor_flag 0
        cmp fLDx+1  ;test flags
        trap_ne
        set_stat 0
        lda (ind1+4),z
        php         ;test stores do not alter flags
        eor #$c3
        plp
        sta (indt+4),z
        php         ;flags after load/store sequence
        eor #$c3
        cmp #$41    ;test result
        trap_ne
        pla         ;load status
        eor_flag 0
        cmp fLDx+2  ;test flags
        trap_ne
        set_stat 0
        lda (ind1+6),z
        php         ;test stores do not alter flags
        eor #$c3
        plp
        sta (indt+6),z
        php         ;flags after load/store sequence
        eor #$c3
        cmp #0      ;test result
        trap_ne
        pla         ;load status
        eor_flag 0
        cmp fLDx+3  ;test flags
        trap_ne
        cpx #$99
        trap_ne     ;x altered during test
        cpy #$66
        trap_ne     ;y altered during test

        ldy #3      ;testing store result
        ldx #0
tstai1  lda abst,y
        eor #$c3
        cmp abs1,y
        trap_ne     ;store to indirect data
        txa
        sta abst,y  ;clear
        dey
        bpl tstai1

        ldx #$99    ;protect x & y
        ldy #$66
        set_stat $ff
        lda (ind1),z
        php         ;test stores do not alter flags
        eor #$c3
        plp
        sta (indt),z
        php         ;flags after load/store sequence
        eor #$c3
        cmp #$c3    ;test result
        trap_ne
        pla         ;load status
        eor_flag <~fnz ;mask bits not altered
        cmp fLDx    ;test flags
        trap_ne
        set_stat $ff
        lda (ind1+2),z
        php         ;test stores do not alter flags
        eor #$c3
        plp
        sta (indt+2),z
        php         ;flags after load/store sequence
        eor #$c3
        cmp #$82    ;test result
        trap_ne
        pla         ;load status
        eor_flag <~fnz ;mask bits not altered
        cmp fLDx+1  ;test flags
        trap_ne
        set_stat $ff
        lda (ind1+4),z
        php         ;test stores do not alter flags
        eor #$c3
        plp
        sta (indt+4),z
        php         ;flags after load/store sequence
        eor #$c3
        cmp #$41    ;test result
        trap_ne
        pla         ;load status
        eor_flag <~fnz ;mask bits not altered
        cmp fLDx+2  ;test flags
        trap_ne
        set_stat $ff
        lda (ind1+6),z
        php         ;test stores do not alter flags
        eor #$c3
        plp
        sta (indt+6),z
        php         ;flags after load/store sequence
        eor #$c3
        cmp #0      ;test result
        trap_ne
        pla         ;load status
        eor_flag <~fnz ;mask bits not altered
        cmp fLDx+3  ;test flags
        trap_ne
        cpx #$99
        trap_ne     ;x altered during test
        cpy #$66
        trap_ne     ;y altered during test

        ldy #3      ;testing store result
        ldx #0
tstai2  lda abst,y
        eor #$c3
        cmp abs1,y
        trap_ne     ;store to indirect data
        txa
        sta abst,y  ;clear
        dey
        bpl tstai2
        tsx
        cpx #$ff
        trap_ne     ;sp push/pop mismatch
        next_test

; testing STZ - zp / abs / zp,x / abs,x
        ldy #123    ;protect y
        ldx #4      ;precharge test area
        lda #7
tstz1   sta zpt,x
        asl a
        dex
        bpl tstz1
        ldx #4
        set_a $55,$ff
        stz zpt
        stz zpt+1
        stz zpt+2
        stz zpt+3
        stz zpt+4
        tst_a $55,$ff
tstz2   lda zpt,x   ;verify zeros stored
        trap_ne     ;non zero after STZ zp
        dex
        bpl tstz2
        ldx #4      ;precharge test area
        lda #7
tstz3   sta zpt,x
        asl a
        dex
        bpl tstz3
        ldx #4
        set_a $aa,0
        stz zpt
        stz zpt+1
        stz zpt+2
        stz zpt+3
        stz zpt+4
        tst_a $aa,0
tstz4   lda zpt,x   ;verify zeros stored
        trap_ne     ;non zero after STZ zp
        dex
        bpl tstz4

        ldx #4      ;precharge test area
        lda #7
tstz5   sta abst,x
        asl a
        dex
        bpl tstz5
        ldx #4
        set_a $55,$ff
        stz abst
        stz abst+1
        stz abst+2
        stz abst+3
        stz abst+4
        tst_a $55,$ff
tstz6   lda abst,x   ;verify zeros stored
        trap_ne     ;non zero after STZ abs
        dex
        bpl tstz6
        ldx #4      ;precharge test area
        lda #7
tstz7   sta abst,x
        asl a
        dex
        bpl tstz7
        ldx #4
        set_a $aa,0
        stz abst
        stz abst+1
        stz abst+2
        stz abst+3
        stz abst+4
        tst_a $aa,0
tstz8   lda abst,x   ;verify zeros stored
        trap_ne     ;non zero after STZ abs
        dex
        bpl tstz8

        ldx #4      ;precharge test area
        lda #7
tstz11  sta zpt,x
        asl a
        dex
        bpl tstz11
        ldx #4
tstz15
        set_a $55,$ff
        stz zpt,x
        tst_a $55,$ff
        dex
        bpl tstz15
        ldx #4
tstz12  lda zpt,x   ;verify zeros stored
        trap_ne     ;non zero after STZ zp
        dex
        bpl tstz12
        ldx #4      ;precharge test area
        lda #7
tstz13  sta zpt,x
        asl a
        dex
        bpl tstz13
        ldx #4
tstz16
        set_a $aa,0
        stz zpt,x
        tst_a $aa,0
        dex
        bpl tstz16
        ldx #4
tstz14  lda zpt,x   ;verify zeros stored
        trap_ne     ;non zero after STZ zp
        dex
        bpl tstz14

        ldx #4      ;precharge test area
        lda #7
tstz21  sta abst,x
        asl a
        dex
        bpl tstz21
        ldx #4
tstz25
        set_a $55,$ff
        stz abst,x
        tst_a $55,$ff
        dex
        bpl tstz25
        ldx #4
tstz22  lda abst,x   ;verify zeros stored
        trap_ne     ;non zero after STZ zp
        dex
        bpl tstz22
        ldx #4      ;precharge test area
        lda #7
tstz23  sta abst,x
        asl a
        dex
        bpl tstz23
        ldx #4
tstz26
        set_a $aa,0
        stz abst,x
        tst_a $aa,0
        dex
        bpl tstz26
        ldx #4
tstz24  lda abst,x   ;verify zeros stored
        trap_ne     ;non zero after STZ zp
        dex
        bpl tstz24

        cpy #123
        trap_ne     ;y altered during test
        tsx
        cpx #$ff
        trap_ne     ;sp push/pop mismatch
        next_test


; testing CMP - (zp)
        ldx #$de    ;protect x & y
        ldy #$ad
        set_a $80,0
        cmp (ind1+8),z
        tst_a $80,fc
        set_a $7f,0
        cmp (ind1+8),z
        tst_a $7f,fzc
        set_a $7e,0
        cmp (ind1+8),z
        tst_a $7e,fn
        set_a $80,$ff
        cmp (ind1+8),z
        tst_a $80,~fnz
        set_a $7f,$ff
        cmp (ind1+8),z
        tst_a $7f,~fn
        set_a $7e,$ff
        cmp (ind1+8),z
        tst_a $7e,~fzc
        cpx #$de
        trap_ne     ;x altered during test
        cpy #$ad
        trap_ne     ;y altered during test
        tsx
        cpx #$ff
        trap_ne     ;sp push/pop mismatch
        next_test

; testing logical instructions - AND EOR ORA (zp)
        ldx #$42    ;protect x & y

        ldy #0      ;AND
        lda indAN   ;set indirect address
        sta zpt
        lda indAN+1
        sta zpt+1
tand1
        set_ay  absANa,0
        and (zpt),z
        tst_ay  absrlo,absflo,0
        inc zpt
        iny
        cpy #4
        bne tand1
        dey
        dec zpt
tand2
        set_ay  absANa,$ff
        and (zpt),z
        tst_ay  absrlo,absflo,$ff-fnz
        dec zpt
        dey
        bpl tand2

        ldy #0      ;EOR
        lda indEO   ;set indirect address
        sta zpt
        lda indEO+1
        sta zpt+1
teor1
        set_ay  absEOa,0
        eor (zpt),z
        tst_ay  absrlo,absflo,0
        inc zpt
        iny
        cpy #4
        bne teor1
        dey
        dec zpt
teor2
        set_ay  absEOa,$ff
        eor (zpt),z
        tst_ay  absrlo,absflo,$ff-fnz
        dec zpt
        dey
        bpl teor2

        ldy #0      ;ORA
        lda indOR   ;set indirect address
        sta zpt
        lda indOR+1
        sta zpt+1
tora1
        set_ay  absORa,0
        ora (zpt),z
        tst_ay  absrlo,absflo,0
        inc zpt
        iny
        cpy #4
        bne tora1
        dey
        dec zpt
tora2
        set_ay  absORa,$ff
        ora (zpt),z
        tst_ay  absrlo,absflo,$ff-fnz
        dec zpt
        dey
        bpl tora2

        cpx #$42
        trap_ne     ;x altered during test
        tsx
        cpx #$ff
        trap_ne     ;sp push/pop mismatch
        next_test

; 16-bit inrement/decrement INW/DEW zp
inwdewtest
        ldx #$00
        ldy #$00
        stx zpt+0
        sty zpt+1

chkinw  cpx zpt+0
        trap_ne
        cpy zpt+1
        trap_ne

        inw zpt         ; increment test location
        inx
        bne chkinw      ; haven't wrapped, check next value
        iny
        bne chkinw      ; haven't wrapped, check next value

        ; pre-decrement back to 0xffff
        dew zpt
        dex
        dey

chkdew  cpx zpt+0
        trap_ne
        cpy zpt+1
        trap_ne

        dew zpt         ; increment test location
        dex
        cpx #$ff        ; wrapped?
        bne chkdew      ; haven't wrapped, check next value
        dey
        cpy #$ff        ; wrapped?
        bne chkdew      ; haven't wrapped, check next value
        next_test

    .if I_flag == 3
        cli
    .endif

; jump indirect (test page cross bug is fixed)
        ldx #3          ;prepare table
ji1     lda ji_adr,x
        sta ji_tab,x
        dex
        bpl ji1
        lda #>(ji_px) ;high address if page cross bug
        sta pg_x
        set_stat 0
        lda #'I'
        ldx #'N'
        ldy #'D'        ;N=0, V=0, Z=0, C=0
        jsr (ji_tab)
ji_ret  php             ;either SP or Y count will fail, if we do not hit
        dey
        dey
        dey
        plp
        trap_eq         ;returned flags OK?
        trap_pl
        trap_cc
        trap_vc
        cmp #('I'^$aa)  ;returned registers OK?
        trap_ne
        cpx #('N'+1)
        trap_ne
        cpy #('D'-6)
        trap_ne
        tsx             ;SP check
        cpx #$ff
        trap_ne
        next_test_

; jump indexed indirect
        ldx #11         ;prepare table
jxi1    lda jxi_adr,x
        sta jxi_tab,x
        dex
        bpl jxi1
        lda #>(jxi_px) ;high address if page cross bug
        sta pg_x
        set_stat 0
        lda #'X'
        ldx #4
        ldy #'I'        ;N=0, V=0, Z=0, C=0
        jsr (jxi_tab,x)
jxi_ret php             ;either SP or Y count will fail, if we do not hit
        dey
        dey
        dey
        plp
        trap_eq         ;returned flags OK?
        trap_pl
        trap_cc
        trap_vc
        cmp #('X'^$aa)  ;returned registers OK?
        trap_ne
        cpx #6
        trap_ne
        cpy #('I'-6)
        trap_ne
        tsx             ;SP check
        cpx #$ff
        trap_ne

        lda #<(jxp_ok) ;test with index causing a page cross
        sta jxp_tab
        lda #>(jxp_ok)
        sta jxp_tab+1
        lda #<(jxp_px)
        sta pg_x
        lda #>(jxp_px)
        sta pg_x+1
        ldx #$ff
        jmp (jxp_tab-$ff,x)

jxp_px
        trap            ;page cross by index to wrong page

jxp_ok
        next_test_

        lda test_case
        cmp #test_num
        trap_ne         ;previous test is out of sequence
        lda #$f0        ;mark opcode testing complete
        sta test_case

; final RAM integrity test
;   verifies that none of the previous tests has altered RAM outside of the
;   designated write areas.
        ;check_ram
; *** DEBUG INFO ***
; to debug checksum errors uncomment check_ram in the next_test macro to
; narrow down the responsible opcode.
; may give false errors when monitor, OS or other background activity is
; allowed during previous tests.


; S U C C E S S ************************************************
; -------------
        success         ;if you get here everything went well
; -------------
; S U C C E S S ************************************************
        jmp start       ;run again


; target for the jump indirect test
ji_adr  .word test_ji
        .word ji_ret

        dey
        dey
test_ji
        php             ;either SP or Y count will fail, if we do not hit
        dey
        dey
        dey
        plp
        trap_cs         ;flags loaded?
        trap_vs
        trap_mi
        trap_eq
        cmp #'I'        ;registers loaded?
        trap_ne
        cpx #'N'
        trap_ne
        cpy #('D'-3)
        trap_ne
        pha             ;save a,x
        txa
        pha
        tsx
        cpx #$fb        ;check SP
        trap_ne
        pla             ;restore x
        tax
        set_stat $ff
        pla             ;restore a
        inx             ;return registers with modifications
        eor #$aa        ;N=1, V=1, Z=0, C=1
        rts
        nop
        nop
        trap            ;runover protection
        jmp start       ;catastrophic error - cannot continue

; target for the jsr indirect indexed test
jxi_adr .word  trap_ind
        .word  trap_ind
        .word  test_jxi    ;+4
        .word  jxi_ret     ;+6
        .word  trap_ind
        .word  trap_ind

        dey
        dey
test_jxi
        php             ;either SP or Y count will fail, if we do not hit
        dey
        dey
        dey
        plp
        trap_cs         ;flags loaded?
        trap_vs
        trap_mi
        trap_eq
        cmp #'X'        ;registers loaded?
        trap_ne
        cpx #4
        trap_ne
        cpy #('I'-3)
        trap_ne
        pha             ;save a,x
        txa
        pha
        tsx
        cpx #$fb        ;check SP
        trap_ne
        pla             ;restore x
        tax
        set_stat $ff
        pla             ;restore a
        inx             ;return registers with modifications
        inx
        eor #$aa        ;N=1, V=1, Z=0, C=1
        rts
        nop
        nop
        trap            ;runover protection
        jmp start       ;catastrophic error - cannot continue

; JSR (abs,x) with bad x
        nop
        nop
trap_ind
        nop
        nop
        trap            ;near miss indexed indirect jump
        jmp start       ;catastrophic error - cannot continue

;trap in case of unexpected IRQ, NMI, BRK, RESET
nmi_trap
        trap            ;check stack for conditions at NMI
        jmp start       ;catastrophic error - cannot continue
res_trap
        trap            ;unexpected RESET
        jmp start       ;catastrophic error - cannot continue
irq_trap
        trap            ;unexpected BRK
        jmp start       ;catastrophic error - cannot continue

    .if report == 1
        include "report.i65"
    .endif

;copy of data to initialize BSS segment
    .if load_data_direct != 1
zp_init
zp1_    .byte  $c3,$82,$41,0   ;test patterns for LDx BIT ROL ROR ASL LSR
zp7f_   .byte  $7f             ;test pattern for compare
;logical zeropage operands
zpOR_   .byte  0,$1f,$71,$80   ;test pattern for OR
zpAN_   .byte  $0f,$ff,$7f,$80 ;test pattern for AND
zpEO_   .byte  $ff,$0f,$8f,$8f ;test pattern for EOR
;indirect addressing pointers
ind1_   .word  abs1            ;indirect pointer to pattern in absolute memory
        .word  abs1+1
        .word  abs1+2
        .word  abs1+3
        .word  abs7f
inw1_   .word  abs1-$f8        ;indirect pointer for wrap-test pattern
indt_   .word  abst            ;indirect pointer to store area in absolute memory
        .word  abst+1
        .word  abst+2
        .word  abst+3
inwt_   .word  abst-$f8        ;indirect pointer for wrap-test store
indAN_  .word  absAN           ;indirect pointer to AND pattern in absolute memory
        .word  absAN+1
        .word  absAN+2
        .word  absAN+3
indEO_  .word  absEO           ;indirect pointer to EOR pattern in absolute memory
        .word  absEO+1
        .word  absEO+2
        .word  absEO+3
indOR_  .word  absOR           ;indirect pointer to OR pattern in absolute memory
        .word  absOR+1
        .word  absOR+2
        .word  absOR+3
;add/subtract indirect pointers
adi2_   .word  ada2            ;indirect pointer to operand 2 in absolute memory
sbi2_   .word  sba2            ;indirect pointer to complemented operand 2 (SBC)
adiy2_  .word  ada2-$ff        ;with offset for indirect indexed
sbiy2_  .word  sba2-$ff
zp_end
    .if (zp_end - zp_init) != (zp_bss_end - zp_bss)
        ;force assembler error if size is different
        ERROR ERROR ERROR   ;mismatch between bss and zeropage data
    .endif
data_init
ex_adc_ adc #0              ;execute immediate opcodes
        rts
ex_sbc_ sbc #0              ;execute immediate opcodes
        rts
abs1_   .byte  $c3,$82,$41,0   ;test patterns for LDx BIT ROL ROR ASL LSR
abs7f_  .byte  $7f             ;test pattern for compare
;loads
fLDx_   .byte  fn,fn,0,fz      ;expected flags for load
;shifts
rASL_                       ;expected result ASL & ROL -carry
rROL_   .byte  $86,$04,$82,0   ; "
rROLc_  .byte  $87,$05,$83,1   ;expected result ROL +carry
rLSR_                       ;expected result LSR & ROR -carry
rROR_   .byte  $61,$41,$20,0   ; "
rRORc_  .byte  $e1,$c1,$a0,$80 ;expected result ROR +carry
fASL_                       ;expected flags for shifts
fROL_   .byte  fnc,fc,fn,fz    ;no carry in
fROLc_  .byte  fnc,fc,fn,0     ;carry in
fLSR_
fROR_   .byte  fc,0,fc,fz      ;no carry in
fRORc_  .byte  fnc,fn,fnc,fn   ;carry in
;increments (decrements)
rINC_   .byte  $7f,$80,$ff,0,1 ;expected result for INC/DEC
fINC_   .byte  0,fn,fn,fz,0    ;expected flags for INC/DEC
;logical memory operand
absOR_  .byte  0,$1f,$71,$80   ;test pattern for OR
absAN_  .byte  $0f,$ff,$7f,$80 ;test pattern for AND
absEO_  .byte  $ff,$0f,$8f,$8f ;test pattern for EOR
;logical accu operand
absORa_ .byte  0,$f1,$1f,0     ;test pattern for OR
absANa_ .byte  $f0,$ff,$ff,$ff ;test pattern for AND
absEOa_ .byte  $ff,$f0,$f0,$0f ;test pattern for EOR
;logical results
absrlo_ .byte  0,$ff,$7f,$80
absflo_ .byte  fz,fn,0,fn
data_end
    .if (data_end - data_init) != (data_bss_end - data_bss)
        ;force assembler error if size is different
        ERROR ERROR ERROR   ;mismatch between bss and data
    .endif

    .if ROM_vectors == 1
vec_init
        .word  nmi_trap
        .word  res_trap
        .word  irq_trap
vec_bss = $fffa
    .endif

    .endif                   ;end of RAM init data

; code at end of image due to the need to add blank space as required
    .if ($ff & (ji_ret - * - 2)) < ($ff & (jxi_ret - * - 2))
; JMP (abs) when $xxff and $xx00 are from same page
        .fill  <(ji_ret - * - 2)
        nop
        nop
ji_px   nop             ;low address byte matched with ji_ret
        nop
        trap            ;jmp indirect page cross bug

; JMP (abs,x) when $xxff and $xx00 are from same page
        .fill  <(jxi_ret - * - 2)
        nop
        nop
jxi_px  nop             ;low address byte matched with jxi_ret
        nop
        trap            ;jmp indexed indirect page cross bug
    .else
; JMP (abs,x) when $xxff and $xx00 are from same page
        .fill  <(jxi_ret - * - 2)
        nop
        nop
jxi_px  nop             ;low address byte matched with jxi_ret
        nop
        trap            ;jmp indexed indirect page cross bug

; JMP (abs) when $xxff and $xx00 are from same page
        .fill  <(ji_ret - * - 2)
        nop
        nop
ji_px   nop             ;low address byte matched with ji_ret
        nop
        trap            ;jmp indirect page cross bug
    .endif

*       = $fffa ;vectors
        .word  nmi_trap
        .word  start
        .word  irq_trap
        .endsegment code

*       = code_segment
        .dsection code
        code

        .end
