#include <sys/asm.h>
#include <sys/regdef.h>
#include <PR/R4300.h>
#include <PR/rcp.h>
#include <PR/os_system.h>

/* Magic value to multiply the IPL3 checksum CIC seed by */
#define IPL3_CHECKSUM_MAGIC 0x6C078965

/* Special locations in PIF RAM */
#define PIF_RAM_CIC_SEED            0x24 /* PIF puts seed received from CIC here before releasing CPU */
#define PIF_RAM_CIC_CHALLENGE_DATA  0x30 /* PIF expects challenge data at this offset */
#define PIF_RAM_IPL3_CHECKSUM_HI    0x30 /* PIF expects calculated IPL3 checksum here to verify it */
#define PIF_RAM_IPL3_CHECKSUM_LO    0x34

#define PIF_RAM_STATUS 0x3C

/* PIF RAM Status (Write) */
#define PIF_CMD_JOYBUS_EXEC     0x01 /* Run joybus protocol using the contents of PIF RAM */
#define PIF_CMD_CHALLENGE       0x02 /* Run X105 challenge/response protocol */
#define PIF_CMD_UNK4            0x04 /* No known function */
#define PIF_CMD_TERMINATE_BOOT  0x08 /* Indicate boot process is done, if not sent within 5 seconds from boot the PIF locks the CPU */
#define PIF_CMD_LOCK_ROM        0x10 /* Unmaps the PIF ROM so it is no longer accessible from the CPU */
#define PIF_CMD_IPL3_CHECKSUM   0x20 /* Send the IPL3 checksum result to the PIF so it can verify it is correct and lock the CPU if not */
#define PIF_CMD_CLR_RAM         0x40 /* Fill the PIF RAM with 0 */

/* PIF RAM Status (Read) */
#define PIF_CMD_CHECKSUM_ACK    0x80 /* PIF received IPL3 checksum result */

/* IPL1 @ 0xBFC00000 (PIF ROM KSEG1) */

#define SHIFTL(v, s, w) (((v) & ((1 << (w)) - 1)) << (s))

#define CONFIG(cm, ec, ep, sb, ss, sw, ew, sc, sm, be, em, eb, ic, dc, icb, dcb, cu, k0) \
    /* Master-Checker enable            */ (SHIFTL( cm, 31, 1) | \
    /* System Clock ratio               */  SHIFTL( ec, 28, 3) | \
    /* Transmit data pattern            */  SHIFTL( ep, 24, 4) | \
    /* Secondary cache block size       */  SHIFTL( sb, 22, 2) | \
    /* Split scache                     */  SHIFTL( ss, 21, 1) | \
    /* Scache port                      */  SHIFTL( sw, 20, 1) | \
    /* System port width                */  SHIFTL( ew, 18, 2) | \
    /* Secondary cache present          */  SHIFTL( sc, 17, 1) | \
    /* Dirty Shared Coherency           */  SHIFTL( sm, 16, 1) | \
    /* Endianness                       */  SHIFTL( be, 15, 1) | \
    /* ECC Mode                         */  SHIFTL( em, 14, 1) | \
    /* Block order                      */  SHIFTL( eb, 13, 1) | \
    /* 0                                */  SHIFTL(  0, 12, 1) | \
    /* Primary icache size              */  SHIFTL( ic,  9, 3) | \
    /* Primary dcache size              */  SHIFTL( dc,  6, 3) | \
    /* Icache block size                */  SHIFTL(icb,  5, 1) | \
    /* Dcache block size                */  SHIFTL(dcb,  4, 1) | \
    /* Update on store conditional      */  SHIFTL( cu,  3, 1) | \
    /* KSEG0 cache coherency algorithm  */  SHIFTL( k0,  0, 3))

ipl1_start:

LEAF(ipl1)
    /* set initial values for C0_SR and C0_CONFIG */

    li      t1, 0x20000000 | 0x10000000 | 0x04000000 /* SR_CU1 | SR_CU0 | SR_FR     why FR? */
    MTC0(   t1, C0_SR)

    li      t1, CONFIG(0, 0, 0, 0, 0, 0, 1, 1, 0, 1, 1, 1, 2, 1, 1, 0, 0, CONFIG_NONCOHRNT)
    MTC0(   t1, C0_CONFIG)

    /* wait for the RSP to report halted */
await_halt:
    lw      t0, PHYS_TO_K1(SP_STATUS_REG)
    andi    t0, SP_STATUS_HALT
    beqz    t0, await_halt

    /* RSP set halt and clear SP interrupt */
    li      t0, SP_SET_HALT | SP_CLR_INTR
    sw      t0, PHYS_TO_K1(SP_STATUS_REG)

    /* wait for any ongoing RSP DMA to complete */
dma_busy:
    lw      t0, PHYS_TO_K1(SP_DMA_BUSY_REG)
    andi    t0, 1
    bnez    t0, dma_busy

    /* reset the PI */
    li      t0, PI_SET_RESET | PI_CLR_INTR
    sw      t0, PHYS_TO_K1(PI_STATUS_REG)

    /* stop the VI */
    li      t0, 1024-1
    sw      t0, PHYS_TO_K1(VI_INTR_REG)
    sw      zero, PHYS_TO_K1(VI_H_START_REG)
    sw      zero, PHYS_TO_K1(VI_CURRENT_REG)

    /* stop the AI */
    sw      zero, PHYS_TO_K1(AI_DRAM_ADDR_REG)
    sw      zero, PHYS_TO_K1(AI_LEN_REG)

    /* again wait for RSP DMA to be inactive, this time using SP_STATUS */
dma_busy2:
    lw      t0, PHYS_TO_K1(SP_STATUS_REG)
    andi    t0, SP_STATUS_DMA_BUSY
    bnez    t0, dma_busy2

    /* copy IPL2 to RSP IMEM */
    la      t3, PHYS_TO_K1(SP_IMEM_START)
    la      t4, ipl2_rom
    la      t5, ipl2_rom_end
ipl2_copyloop:
    lw      t1, (t4)
    sw      t1, (t3)
    addiu   t4, 4
    addiu   t3, 4
    bne     t4, t5, ipl2_copyloop

    /* set up a stack at the end of RSP IMEM */
    li      sp, PHYS_TO_K1(SP_IMEM_END - 0xF)
    /* jump to RSP IMEM */
    la      t3, PHYS_TO_K1(SP_IMEM_START)
    jr      t3
END(ipl1)

/* IPL2 @ 0xA4001000 (IMEM start KSEG1) */

ipl2_rom:

LEAF(ipl2)
    /* wait for PIF_CMD_CHECKSUM_ACK  to be unset in PIF control/status */
loop:
    la      t5, PHYS_TO_K1(PIF_RAM_START)
    lw      t0, PIF_RAM_STATUS(t5)
    andi    t0, PIF_CMD_CHECKSUM_ACK 
    bnez    t0, loop

    /*
     * Load values that were placed in PIF RAM before CPU boot
     *
     * Format:
     *  [ 0: 7] IPL3 checksum "seed"
     *  [ 8:15] ROM checksum "seed", passed to IPL3
     *  [   16] ?
     *  [   17] osResetType     0=cold reset , 1=soft reset
     *  [   18] osVersion
     *  [   19] osRomType       0=cart , 1=n64dd
     */
    lw      t0, PIF_RAM_CIC_SEED(t5)
    /* osVersion */
    srl     s7, t0, 18
    andi    s7, 1
#if defined(PIFROM_PAL)
    ori     s7, 6
#elif defined(PIFROM_MPAL)
    ori     s7, 4
#endif
    /* osRomType */
    srl     s3, t0, 19
    andi    s3, 1

    /* Select cart domain based on rom type */
    li      t3, PHYS_TO_K1(PI_DOM1_ADDR2) /* cart rom base */
    beqz    s3, 1f
    li      t3, PHYS_TO_K1(PI_DOM1_ADDR1) /* DD rom base ? */
1:

    srl     s6, t0, 8
    andi    s6, 0xFF
    andi    t2, t0, 0xFF
    /* osResetType */
    srl     s5, t0, 17
    andi    s5, 1
    /* osTvType */
#if defined(PIFROM_PAL)
    li      s4, OS_TV_PAL
#elif defined(PIFROM_MPAL)
    li      s4, OS_TV_MPAL
#else
    li      s4, OS_TV_NTSC
#endif

    /* Lock the PIF ROM */
    li      t1, PIF_CMD_LOCK_ROM
    lw      t0, PIF_RAM_STATUS(t5)
    or      t0, t1
si_wait:
    lw      t1, PHYS_TO_K1(SI_STATUS_REG)
    andi    t1, SI_STATUS_RD_BUSY
    bnez    t1, si_wait

    sw      t0, PIF_RAM_STATUS(t5)

    /* Set default PI Domain 1 configuration to read the ROM header */
    la      t4, PHYS_TO_K1(PI_BASE_REG)
    li      t0, 255
    sw      t0, (PI_BSD_DOM1_LAT_REG - PI_BASE_REG)(t4)
    sw      t0, (PI_BSD_DOM1_PWD_REG - PI_BASE_REG)(t4)
    li      t0, 15
    sw      t0, (PI_BSD_DOM1_PGS_REG - PI_BASE_REG)(t4)
    li      t0, 3
    sw      t0, (PI_BSD_DOM1_RLS_REG - PI_BASE_REG)(t4)

    /* Read PI Domain 1 configuration from the ROM header */
    lw      t1, (t3)

    /* Set PI Domain 1 configuration */
    andi    t0, t1, 0xFF
    sw      t0, (PI_BSD_DOM1_LAT_REG - PI_BASE_REG)(t4)
    srl     t0, t1, 8
    sw      t0, (PI_BSD_DOM1_PWD_REG - PI_BASE_REG)(t4)
    srl     t0, t1, 0x10
    sw      t0, (PI_BSD_DOM1_PGS_REG - PI_BASE_REG)(t4)
    srl     t0, t1, 0x14
    sw      t0, (PI_BSD_DOM1_RLS_REG - PI_BASE_REG)(t4)

    addi    t0, zero, 0xFC0
    addi    t3, t3, 0x40

    /* Check if RDP DMA method is XBUS */
    la      t5, PHYS_TO_K1(DPC_STATUS_REG)
    lw      t7, (t5)
    andi    t7, t7, DPC_STATUS_XBUS_DMEM_DMA
    beqz    t7, not_xbus_dma

    /* If XBUS, wait for RDP pipeline idle */
pipe_busy:
    la      t5, PHYS_TO_K1(DPC_STATUS_REG)
    lw      t7, (t5)
    andi    t7, t7, DPC_STATUS_PIPE_BUSY
    bnez    t7, pipe_busy

    /* Copy IPL3 to RSP DMEM */
not_xbus_dma:
    la      t5, PHYS_TO_K1(SP_DMEM_START)
    or      a2, zero, t0
    addi    t5, t5, 0x40
ipl3_copyloop:
    lw      t1, (t3)
    sw      t1, (t5)
    addi    t3, 4
    addi    t5, 4
    addi    t0, -4
    bnez    t0, ipl3_copyloop

    /* Compute and verify IPL3 checksum */
.set noreorder
    li      t0, 0x6C078965
    multu   t2, t0
    mflo    a0
    addiu   a0, 1
    la      a1, PHYS_TO_K1(SP_DMEM_START + 0x40)
.set reorder
    bal     CalcChecksum
END(ipl2)

/**
 *  Inputs:     a0, a1, a2
 *  Outputs:    v0
 *  Clobbers:   a0, a2, a3, v0, v1, t6, t7
 */
LEAF(subroutine_1210)
    addiu   sp, sp, -0x30
    sw      ra, 0x1C(sp)
    bnez    a1, 1f          # if (a1 == 0)
    move    a1, a2          #     a1 = a2
1:
    addiu   a2, sp, 0x2C
    addiu   a3, sp, 0x28
    bal     mult_64bit      # mult = a0 * a1
    lw      a0, 0x28(sp)
    lw      t6, 0x2C(sp)
    subu    v0, t6, a0      # v0 = hi(mult) - lo(mult)
    move    v1, v0          # v1 = v0
    bnez    v0, 2f          # if (v0 == 0)
    move    v1, a0          #     v1 = lo(mult)
2:
    lw      ra, 0x1C(sp)
    addiu   sp, sp, 0x30
    move    v0, v1          # v0 = v1
    jr      ra
END(subroutine_1210)

LEAF(CalcChecksum)
    addiu   sp, sp, -0xE0
    sw      ra, 0x3C(sp)
    sw      s7, 0x34(sp)
    sw      s6, 0x30(sp)
    sw      s5, 0x2C(sp)
    sw      s4, 0x28(sp)
    sw      s3, 0x24(sp)
    sw      s2, 0x20(sp)
    sw      s1, 0x1C(sp)
    sw      s0, 0x18(sp)
    lw      t6, (a1)
    move    v1, zero
    addiu   v1, sp, 0xB4
    addiu   v0, sp, 0x74
    xor     s0, t6, a0

lbl_294:
    sw      s0, 4(v0)
    sw      s0, 8(v0)
    sw      s0, 0xC(v0)
    sw      s0, (v0)
    addiu   v0, v0, 16
    bne     v0, v1, lbl_294

    lw      s0, (a1)
    move    s1, zero
    move    s6, a1
    li      s7, 32
lbl_2bc:
    move    s4, s0
    lw      s0, (s6)
    addiu   s1, s1, 1
    li      t7, 1007
    lw      s3, 4(s6)
    addiu   s6, s6, 4
    subu    a0, t7, s1
    move    a2, s1
    move    a1, s0
    bal     subroutine_1210

    lw      v1, 0x74(sp)
    lw      a0, 0x78(sp)
    move    a1, s0
    addu    v1, v0, v1
    sw      v1, 0x74(sp)
    move    a2, s1
    bal     subroutine_1210

    lw      t8, 0x7C(sp)
    sw      v0, 0x78(sp)
    xor     t9, t8, s0
    sw      t9, 0x7C(sp)
    li      a1, 0x6C078965
    addiu   a0, s0, 5
    move    a2, s1
    bal     subroutine_1210

    lw      t0, 0x80(sp)
    addu    t1, v0, t0
    sw      t1, 0x80(sp)
    bgeu    s4, s0, lbl_350

    lw      a0, 0x98(sp)
    move    a1, s0
    move    a2, s1
    bal     subroutine_1210

    sw      v0, 0x98(sp)
    b       lbl_35c

lbl_350:
    lw      t2, 0x98(sp)
    addu    t3, t2, s0
    sw      t3, 0x98(sp)

lbl_35c:
    andi    v0, s4, 0x1F
    lw      t6, 0x84(sp)
    subu    v1, s7, v0
    sllv    t5, s0, v1
    srlv    t4, s0, v0
    or      s5, t4, t5
    srlv    t9, s0, v1
    sllv    t8, s0, v0
    addu    t7, t6, s5
    sw      t7, 0x84(sp)
    or      a1, t8, t9
    lw      a0, 0x90(sp)
    move    a2, s1
    bal     subroutine_1210

    lw      v1, 0x8C(sp)
    sw      v0, 0x90(sp)
    bgeu    s0, v1, lbl_3c4
    lw      t0, 0x80(sp)
    addu    t2, s0, s1
    addu    t1, t0, v1
    xor     v1, t1, t2
    sw      v1, 0x8C(sp)
    b       lbl_3d0

lbl_3c4:
    lw      t3, 0x84(sp)
    addu    t4, t3, s0
    xor     v1, t4, v1
    sw      v1, 0x8C(sp)

lbl_3d0:
    srl     v0, s4, 0x1B
    lw      t7, 136(sp)
    subu    v1, s7, v0
    srlv    t6, s0, v1
    sllv    t5, s0, v0
    or      s2, t5, t6
    sllv    t0, s0, v1
    srlv    t9, s0, v0
    addu    t8, t7, s2
    sw      t8, 136(sp)
    or      a1, t9, t0
    lw      a0, 148(sp)
    move    a2, s1
    bal     subroutine_1210

    sw      v0, 0x94(sp)
    beq     s1, 1008, lbl_4f4
    lw      a0, 0xB0(sp)
    move    a1, s2
    move    a2, s1
    bal     subroutine_1210

    srl     v1, s0, 0x1B
    subu    t2, s7, v1
    srlv    t3, s3, t2
    sllv    t1, s3, v1
    or      a1, t1, t3
    move    a0, v0
    move    a2, s1
    bal     subroutine_1210

    sw      v0, 0xB0(sp)
    lw      a0, 0xAC(sp)
    move    a1, s5
    move    a2, s1
    bal     subroutine_1210

    andi    s2, s0, 0x1F
    subu    s4, s7, s2
    sllv    t5, s3, s4
    srlv    t4, s3, s2
    or      a1, t4, t5
    move    a0, v0
    move    a2, s1
    bal     subroutine_1210

    lw      t1, 0xA8(sp)
    andi    v1, s3, 0x1F
    srlv    t6, s0, s2
    sllv    t7, s0, s4
    subu    t9, s7, v1
    or      a3, t6, t7
    sllv    t0, s3, t9
    srlv    t8, s3, v1
    lw      t5, 0x9C(sp)
    or      t2, t8, t0
    addu    t3, t1, a3
    addu    t4, t3, t2
    sw      v0, 0xAC(sp)
    sw      t4, 0xA8(sp)
    move    a1, s3
    move    a2, s1
    addu    a0, t5, s0
    bal     subroutine_1210

    lw      t6, 0xA0(sp)
    sw      v0, 0x9C(sp)
    move    a1, s3
    move    a2, s1
    xor     a0, t6, s0
    bal     subroutine_1210

    lw      t7, 0x94(sp)
    lw      t8, 0xA4(sp)
    sw      v0, 0xA0(sp)
    xor     t9, t7, s0
    addu    t0, t9, t8
    sw      t0, 0xA4(sp)
    b       lbl_2bc

lbl_4f4:
    lw      v1, 0x74(sp)
    move    s1, zero
    addiu   s3, sp, 0x74
    li      s5, 16
    li      s4, 1
    sw      v1, 0x64(sp)
    sw      v1, 0x68(sp)
    sw      v1, 0x6C(sp)
    sw      v1, 0x70(sp)
lbl_1518:
    lw      s0, (s3)
    lw      t5, 0x64(sp)
    andi    v0, s0, 0x1F
    subu    t3, s7, v0
    sllv    t2, s0, t3
    srlv    t1, s0, v0
    or      t4, t1, t2
    addu    t6, t5, t4
    sw      t6, 0x64(sp)
    bgeu    s0, t6, lbl_554

    lw      t7, 0x68(sp)
    addu    t9, t7, s0
    sw      t9, 0x68(sp)
    b       lbl_568

lbl_554:
    lw      a0, 0x68(sp)
    move    a1, s0
    move    a2, s1
    bal     subroutine_1210
    sw      v0, 0x68(sp)
lbl_568:
    andi    t8, s0, 2
    srl     t0, t8, 1
    andi    s2, s0, 1
    bne     t0, s2, lbl_590

    lw      t3, 0x6C(sp)
    addu    t1, t3, s0
    sw      t1, 0x6C(sp)
    b       lbl_5a0

lbl_590:
    lw      a0, 0x6C(sp)
    move    a1, s0
    move    a2, s1
    bal     subroutine_1210

    sw      v0, 0x6C(sp)
lbl_5a0:
    bne     s4, s2, lbl_5bc
    lw      t2, 0x70(sp)
    xor     t5, t2, s0
    sw      t5, 0x70(sp)
    b       lbl_5cc

lbl_5bc:
    lw      a0, 0x70(sp)
    move    a1, s0
    move    a2, s1
    bal     subroutine_1210

    sw      v0, 0x70(sp)
lbl_5cc:
    addiu   s1, s1, 1
    addiu   s3, s3, 4
    bne     s1, s5, lbl_1518

    lw      a0, 0x64(sp)
    lw      a1, 0x68(sp)
    move    a2, s1
    bal     subroutine_1210

    lw      t4, 0x70(sp)
    lw      t6, 0x6C(sp)
    lw      s0, 0x18(sp)
    lw      s1, 0x1C(sp)
    lw      s2, 0x20(sp)
    lw      s3, 0x24(sp)
    lw      s4, 0x28(sp)
    lw      s5, 0x2C(sp)
    lw      s6, 0x30(sp)
    lw      s7, 0x34(sp)
    lw      ra, 0x3C(sp)

    move    a0, v0
    addiu   sp, sp, 0xE0
    xor     a1, t4, t6
    bal     subroutine_1640
END(CalcChecksum)

/**
 * Multiply two 32-bit values in a0 and a1, producing a 64-bit result.
 *  The upper 32 bits are stored to the memory location in a2,
 *  the lower 32 bits are stored to the memory location in a3
 *
 *  Inputs:     a0, a1, a2, a3
 *  Outputs:    32 bits @ 0(a2), 32 bits @ 0(a3)
 *  Clobbers:   t6, t7
 */
LEAF(mult_64bit)
    multu   a0, a1
    mfhi    t6
    sw      t6, (a2)
    mflo    t7
    sw      t7, (a3)
    jr      ra
END(mult_64bit)

LEAF(subroutine_1640)
    /* Write calculated IPL3 checksum into PIF RAM */

    /* TODO figure out how to write this properly. la is very close but the generated addiu
       does not reorder past the or as in the original.

    la      t3, PHYS_TO_K1(PIF_RAM_START)
    lw      t0, PIF_RAM_IPL3_CHECKSUM_HI(t3)
    */
    andi    a0, a0, 0xFFFF
    lui     t3, PHYS_TO_K1(PIF_RAM_START) >> 16
    lw      t0, (PHYS_TO_K1(PIF_RAM_START + PIF_RAM_IPL3_CHECKSUM_HI) & 0xFFFF)(t3)
    li      t2, 0xFFFF0000
    and     t0, t0, t2
    or      a0, a0, t0
    addiu   t3, t3, PHYS_TO_K1(PIF_RAM_START) & 0xFFFF

lbl_660:
    lw      t1, PHYS_TO_K1(SI_STATUS_REG)
    andi    t1, SI_STATUS_RD_BUSY
    bnez    t1, lbl_660

    sw      a0, PIF_RAM_IPL3_CHECKSUM_HI(t3)

    NOP
    NOP
    NOP
    NOP
    NOP

lbl_68c:
    lw      t1, PHYS_TO_K1(SI_STATUS_REG)
    andi    t1, SI_STATUS_RD_BUSY
    bnez    t1, lbl_68c

    sw      a1, PIF_RAM_IPL3_CHECKSUM_LO(t3)

    /* Send IPL3 checksum to the PIF */
    lw      t0, PIF_RAM_STATUS(t3)
    li      t1, PIF_CMD_IPL3_CHECKSUM
    or      t0, t0, t1
lbl_6b0:
    lw      t1, PHYS_TO_K1(SI_STATUS_REG)
    andi    t1, SI_STATUS_RD_BUSY
    bnez    t1, lbl_6b0
    sw      t0, PIF_RAM_STATUS(t3)

    /* Wait until the PIF acknowledges that the checksum was received before continuing.
       If the checksum was wrong the PIF will eventually lock the CPU itself. */
lbl_6c8:
    addi    t1, zero, 16
lbl_6cc:
    addi    t1, -1
    bnez    t1, lbl_6cc

    lw      t0, PIF_RAM_STATUS(t3)
    andi    t2, t0, PIF_CMD_CHECKSUM_ACK
    beq     zero, t2, lbl_6c8

    /* Clear PIF RAM */
    li      t2, PIF_CMD_CLR_RAM
    or      t0, t0, t2
lbl_6f0:
    lw      t1, PHYS_TO_K1(SI_STATUS_REG)
    andi    t1, SI_STATUS_RD_BUSY
    bnez    t1, lbl_6f0

    sw      t0, PIF_RAM_STATUS(t3)

    /* Jump to IPL3 in RSP DMEM + 0x40 */
    la      t3, PHYS_TO_K1(SP_DMEM_START)
    addi    t3, t3, 0x40
    jr      t3
    NOP
END(subroutine_1640)

ipl2_rom_end:

    /* PADDING */
.set noreorder

    /* TODO can we automate the padding to a total size of 0x7C0? IDO pads to the next 0x10 byte
       boundary so it can't be done after compilation with i.e. objcopy */

#if defined(PIFROM_PAL) || defined(PIFROM_MPAL)
.repeat 0xA0
#else
.repeat 0xA4
#endif
    .byte 0xFF
.endr
