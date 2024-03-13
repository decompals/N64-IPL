#include <sys/asm.h>
#include <sys/regdef.h>
#include <PR/R4300.h>
#include <PR/rcp.h>

/* Magic value to multiply the ROM checksum CIC seed by */
#ifdef IPL3_X103
#define ROM_CHECKSUM_MAGIC     0x6C078965
#else
#define ROM_CHECKSUM_MAGIC     0x5D588B65
#endif

#if defined(IPL3_X103)
#define CIC_TYPE    6103
#elif defined(IPL3_X105)
#define CIC_TYPE    6105
#endif

/*
 * http://pdf.datasheetcatalog.com/datasheet/oki/MSM5718B70.pdf     pg21
 */
#define RASINTERVAL(RowPrecharge, RowSense, RowImpRestore, RowExpRestore) \
   ((((RowPrecharge)  & 0x1F) << 24) | \
    (((RowSense)      & 0x1F) << 16) | \
    (((RowImpRestore) & 0x1F) <<  8) | \
    (((RowExpRestore) & 0x1F) <<  0))

/*
 * http://pdf.datasheetcatalog.com/datasheet/oki/MSM5718B70.pdf     pg20
 */
#define RDRAM_DELAY(AckWinDelay, ReadDelay, AckDelay, WriteDelay) \
   ((((AckWinDelay) & 7) << 3 << 24) | \
    (((ReadDelay)   & 7) << 3 << 16) | \
    (((AckDelay)    & 3) << 3 <<  8) | \
    (((WriteDelay)  & 7) << 3 <<  0))

#define ROT16(x) ((((x) & 0xFFFF0000) >> 16) | (((x) & 0xFFFF) << 16))

#define DEVICE_TYPE(Bank, Row, Col, Bonus, EnhancedSpeed, Version, Type) \
   ((((Col)           & 0xF) << 28) | \
    (((Bonus)         &   1) << 26) | \
    (((EnhancedSpeed) &   1) << 24) | \
    (((Bank)          & 0xF) << 20) | \
    (((Row)           & 0xF) << 16) | \
    (((Version)       & 0xF) <<  4) | \
    (((Type)          & 0xF) <<  0))

#define RDRAM_DEVICE_TYPE_ES    (1 << 24)   /* Enhanced speed */

#define RDRAM_MANUFACTURER_NEC  0x500

#define RI_REFRESH(Banks, Optimize, Enable, Bank, DirtyDelay, CleanDelay) \
   ((((Banks)      & 0x1FFF) << 19) | \
    (((Optimize)   &      1) << 18) | \
    (((Enable)     &      1) << 17) | \
    (((Bank)       &      1) << 16) | \
    (((DirtyDelay) &   0xFF) <<  8) | \
    (((CleanDelay) &   0xFF) <<  0))

#define RI_CONFIG_CC_AUTO 0x40

#define RDRAM_MODE_DEVICE_ENABLE    0x02000000 /*DE=1*/
#define RDRAM_MODE_AUTO_SKIP        0x04000000 /*AS=1*/
#define RDRAM_MODE_CC_MULT          0x40000000 /*X2=1*/
#define RDRAM_MODE_CC_ENABLE        0x80000000 /*CE=1*/

#define CC_AUTO   1
#define CC_MANUAL 2

/* IPL3 @ 0xA4000040 (DMEM + 0x40 KSEG1) */

#ifdef IPL3_X105

LEAF(ipl3_entry)
.set noreorder
    add     t1, sp, zero /* sp is somewhere in a stack at the end of IMEM */
1:
    lw      t0, -0xFF0(t1)
    lw      t2, 0x44(t3) /* t3 = DMEM + 0x40, loads from 0xA4000088 */
    xor     t2, t2, t0
    sw      t2, -0xFF0(t1)
    addi    t3, t3, 4
    andi    t0, t0, 0xfff
    bnez    t0, 1b
     addi   t1, t1, 4

    lw      t0, 0x44(t3)
    lw      t2, 0x48(t3)
    sw      t0, -0xFF0(t1)
    sw      t2, -0xFEC(t1)
    bltz    ra, ipl3
     sw     zero, -0xFE8(t1)
.set reorder
END(ipl3_entry)

.set noreorder

.word 0x00000000, 0x00000000

/* 0xA4000088, used by above code */
.word 0x7C1C97C0, 0x9B88F802, 0x05BC16E0, 0x71990080, 0x7511FE14, 0x7C9CB7C0, 0xCD391024, 0x2A2B4FFF
.word 0x40113000, 0x0800046E, 0x3C0BA4B0, 0x01600008, 0x02F3B820

.set reorder
#endif /* IPL3_X105 */

LEAF(ipl3)
    MTC0(   zero, C0_CAUSE)
    MTC0(   zero, C0_COUNT)
    MTC0(   zero, C0_COMPARE)

    la      t0, PHYS_TO_K1(RI_BASE_REG)
    lw      t1, (RI_SELECT_REG - RI_BASE_REG)(t0)
.set noreorder
    bnez    t1, nmi
     nop

    addiu   sp, sp, -0x18
    sw      s3, 0(sp)
    sw      s4, 4(sp)
    sw      s5, 8(sp)
    sw      s6, 0xC(sp)
    sw      s7, 0x10(sp)
    la      t0, PHYS_TO_K1(RI_BASE_REG)

    /* writes to RDRAM registers through the global config will be broadcast to all units */
    li      t2, PHYS_TO_K1(RDRAM_BASE_REG | RDRAM_GLOBAL_CONFIG)
    /* write only to the currently selected unit */
    li      t3, PHYS_TO_K1(RDRAM_BASE_REG)

    la      t4, PHYS_TO_K1(MI_BASE_REG)

    /* set current control to automatic */
    ori     t1, zero, RI_CONFIG_CC_AUTO
    sw      t1, (RI_CONFIG_REG - RI_BASE_REG)(t0)

#if defined(IPL3_X103) || defined (IPL3_X106)
    /* wait 8800 */
    li      s1, 8800
#else
    /* wait 8000 */
    li      s1, 8000
#endif
wait_rac:
    nop
    addi    s1, s1, -1
    bnez    s1, wait_rac
     nop

    sw      zero, (RI_CURRENT_LOAD_REG - RI_BASE_REG)(t0)

    /* Enable TX/RX select */
    ori     t1, zero, 0x10 | 4
    sw      t1, (RI_SELECT_REG - RI_BASE_REG)(t0)

    /* Mode reset, stop active TX/RX disabled */
    sw      zero, (RI_MODE_REG - RI_BASE_REG)(t0)

    /* wait */
    li      s1, 4
wait_rac1:
    nop
    addi    s1, s1, -1
    bnez    s1, wait_rac1
     nop

    /* set standby, stop active TX, stop active RX */
    ori     t1, zero, 2 | 4 | 8
    sw      t1, (RI_MODE_REG - RI_BASE_REG)(t0)

#ifndef IPL3_6101
    /* wait */
    li      s1, 32
wait_rdram:
    addi    s1, s1, -1
    bnez    s1, wait_rdram
#endif /* !IPL3_6101 */

    /* 
     * Set MI init mode, length 15. This equentially repeats the next written value on the bus for 16 bytes total.
     * e.g. for a word write 0xAABBCCDD the write data is extended to 0xAABBCCDDAABBCCDDAABBCCDDAABBCCDD
     *
     * This is required as the RDRAM delays have yet to be configured, so RDRAM transactions (including register
     * read/write) do not behave correctly. For timings to work out when writing the delay register the value must be
     * rotated by 16 bits and repeated for the delay register to be set to the correct value under the default delay
     * configuration.
     *
     * https://n64brew.dev/wiki/RDRAM#Reset_Complications
     */
     ori    t1, zero, MI_SET_INIT | 15
    sw      t1, (MI_INIT_MODE_REG - MI_BASE_REG)(t4)

    /* Set all Delays: AckWin=5, Read=7, Ack=3, Write=1 */
    /* This must be the next bus write following setting MI Init mode for the reason explained above */
    li      t1, ROT16(RDRAM_DELAY(5, 7, 3, 1))
    sw      t1, (RDRAM_DELAY_REG - RDRAM_BASE_REG)(t2)

    /* Set all Refresh Row to 0 */
    sw      zero, (RDRAM_REF_ROW_REG - RDRAM_BASE_REG)(t2)

    /* Move all RDRAMs to physical address 0x2000000 */
    li      t1, 0x2000000 << 6
    sw      t1, (RDRAM_DEVICE_ID_REG - RDRAM_BASE_REG)(t2)

#define NumModules          t5
#define InitialDeviceID     t6
#define InitialRegBase      t7
#define FinalDeviceID_1M    t8
#define FinalRegBase_1M     t9
#define TestAddr_1M         s6
#define FinalDeviceID_2M    s7
#define FinalRegBase_2M     a2
#define TestAddr_2M         a3
#define ModuleBitmask_2M    s2
#define CCTestAddr          s4

    move    NumModules, zero
    move    InitialDeviceID, zero
    li      InitialRegBase, PHYS_TO_K1(RDRAM_BASE_REG)
    move    FinalDeviceID_1M, zero
    li      FinalRegBase_1M, PHYS_TO_K1(RDRAM_BASE_REG)
    li      TestAddr_1M, K1BASE
    move    FinalDeviceID_2M, zero
    li      FinalRegBase_2M, PHYS_TO_K1(RDRAM_BASE_REG)
    li      TestAddr_2M, K1BASE
    move    ModuleBitmask_2M, zero
    li      CCTestAddr, K1BASE  /* Where in memory to do CC value testing */

    addiu   sp, sp, -0x48
    move    s8, sp

    /* check RCP silicon version */
    lw      s0, PHYS_TO_K1(MI_VERSION_REG)
    la      s1, 0x1010101 /* RSP:01 RDP:01 RAC:01 IO:01 */
    bne     s0, s1, rcp2
     nop
    /* RCP 1.0 */
    li      s0, 1 << 9     /* RCP 1.0 RDRAM regs spacing */
    ori     s1, t3, (0x2000000 >> 20) << 9
    b       loop1
     nop
rcp2:
    /* RCP 2.0 */
    li      s0, 1 << 10    /* RCP 2.0 RDRAM regs spacing */
    ori     s1, t3, (0x2000000 >> 20) << 10

    /**
     * Notes on RDRAM structure:
     *
     * RDRAMs are divided into:
     *  Physical chip, which are split into some number of
     *   Modules, which consist of
     *    Banks, divided up into
     *     Rows and Columns
     *
     * Modules are in one-to-one correspondence with the memory-mapped RDRAM registers.
     *
     * For RDRAM used by the N64:
     * - only the 4MB chips are divided into multiple modules (2x 2MB). Otherwise they contain only one module
     *    (either 2MB or 1MB)
     * - banks are always 1MB large so 2MB modules contain 2 banks and 1MB modules contain a single bank.
     * - rows are 0x800 / 2048 bytes large.
     *
     * Note that above we ignored the 9th bit per byte in each measurement.
     */

    /* detect present RDRAM modules and compute the Current Control (CC) value for them */
loop1:
    /* set the first responder to the first available device ID */
    sw      InitialDeviceID, (RDRAM_DEVICE_ID_REG - RDRAM_BASE_REG)(s1)

    /* try to find an appropriate CC value for this module */
    addiu   s5, InitialRegBase, RDRAM_MODE_REG - RDRAM_BASE_REG
    jal     InitCCValue
     nop
    /* failed, assume no module */
    beqz    v0, loop1_break
     nop
    /* save computed CC value for later */
    sw      v0, (sp)

    /* determine module size by reading the RDRAM device type register */
    li      t1, MI_SET_RDRAM
    sw      t1, (MI_INIT_MODE_REG - MI_BASE_REG)(t4)
    lw      t3, (RDRAM_DEVICE_TYPE_REG - RDRAM_BASE_REG)(InitialRegBase)
    li      t0, 0xF0FF0000  /* Extracts 3x 4-bit values: Number of column/row/bank address bits for this module */
    and     t3, t3, t0
    sw      t3, 4(sp) /* save device type for later */
    addi    sp, sp, 8
    li      t1, MI_CLR_RDRAM
    sw      t1, (MI_INIT_MODE_REG - MI_BASE_REG)(t4)
    li      t0, DEVICE_TYPE(1, 9, 11, 0, 0, 0, 0)   /* BNK=1 , ROW=9 , COL=11 => (1 << 1) * (1 << 9) * (1 << 11) = 2MB */
    bne     t3, t0, SM
     nop

    /* 2MB module */
    li      t0, 0x200000 << 6
    add     FinalDeviceID_1M, FinalDeviceID_1M, t0

    /* Increment 1MB reg base by 2x reg spacing */
    add     FinalRegBase_1M, FinalRegBase_1M, s0
    add     FinalRegBase_1M, FinalRegBase_1M, s0

    /* Increment test addresses */
    li      t0, 0x200000                /* 2MB */
    add     TestAddr_1M, TestAddr_1M, t0
    add     CCTestAddr, CCTestAddr, t0

    /* Only 2MB modules are flagged? */
    sll     ModuleBitmask_2M, ModuleBitmask_2M, 1
    addi    ModuleBitmask_2M, ModuleBitmask_2M, 1
    b       LM
     nop
SM:
    /* 1MB module */
    /* Increment test address */
    li      t0, 0x100000                /* 1MB */
    add     CCTestAddr, CCTestAddr, t0

LM:
    /* Determine the device manufacturer and set appropriate RAS Interval */
    li      t0, MI_SET_RDRAM
    sw      t0, (MI_INIT_MODE_REG - MI_BASE_REG)(t4)
    lw      t1, (RDRAM_DEVICE_MANUF_REG - RDRAM_BASE_REG)(InitialRegBase)
    lw      k0, (RDRAM_DEVICE_TYPE_REG - RDRAM_BASE_REG)(InitialRegBase)
    li      t0, MI_CLR_RDRAM
    sw      t0, (MI_INIT_MODE_REG - MI_BASE_REG)(t4)

    andi    t1, t1, 0xFFFF
    li      t0, RDRAM_MANUFACTURER_NEC  /* NEC Manufacturer ID */
    bne     t1, t0, toshiba
     nop
    li      k1, RDRAM_DEVICE_TYPE_ES
    and     k0, k0, k1
    bnez    k0, toshiba
     nop
/*other:*/
    li      t0, RASINTERVAL(16, 28, 10, 4)
    sw      t0, (RDRAM_RAS_INTERVAL_REG - RDRAM_BASE_REG)(InitialRegBase)
    b       done_manufacture
toshiba:
     li     t0, RASINTERVAL(8, 12, 18, 4)
    sw      t0, (RDRAM_RAS_INTERVAL_REG - RDRAM_BASE_REG)(InitialRegBase)

done_manufacture:
    /* Increment device id by 2MB (regardless of whether it was a 2MB or 1MB module? bug? since CCTestAddr goes out of sync) */
    li      t0, 0x200000 << 6
    add     InitialDeviceID, InitialDeviceID, t0
    /* Increment RDRAM reg base by 2x reg spacing (also regardless of 2MB or 1MB? also bug?) */
    add     InitialRegBase, InitialRegBase, s0
    add     InitialRegBase, InitialRegBase, s0

    addiu   NumModules, NumModules, 1
    /* Only try up to 8 modules (either 1M or 2M for possible maximum of 16MB installed memory?) */
    sltiu   t0, NumModules, 8
    bnez    t0, loop1
     nop
loop1_break:

    /* move all modules to their final address space, sorting 2MB modules before 1MB modules */

    /* broadcast global mode value and move all modules to address 0x2000000 */
    li      t0, RDRAM_MODE_CC_MULT | RDRAM_MODE_CC_ENABLE | RDRAM_MODE_AUTO_SKIP
    sw      t0, (RDRAM_MODE_REG - RDRAM_BASE_REG)(t2)
    li      t0, 0x2000000 << 6
    sw      t0, (RDRAM_DEVICE_ID_REG - RDRAM_BASE_REG)(t2)

    move    sp, s8
    move    v1, zero
loop2:
    lw      t1, 4(sp)   /* reload saved device type */
    li      t0, DEVICE_TYPE(0, 9, 11, 0, 0, 0, 0)   /* BNK=1 , ROW=9 , COL=11 => (1 << 0) * (1 << 9) * (1 << 11) = 1MB */
    bne     t1, t0, HM
     nop

    /* 1MB Module */
    /* Set Device ID for first responder */
    sw      FinalDeviceID_1M, (RDRAM_DEVICE_ID_REG - RDRAM_BASE_REG)(s1)

    /* Write optimal CC value (auto) */
    addiu   s5, FinalRegBase_1M, (RDRAM_MODE_REG - RDRAM_BASE_REG)
    lw      a0, (sp) /* Reload CC value computed prior */
    addi    sp, sp, 8
    li      a1, CC_AUTO
    jal     WriteCC
     nop

    /* 4 reads @ (TestAddr_1M) x2 & (TestAddr_1M + 0x80000) x2 */
    lw      t0, (TestAddr_1M)
    li      t0, 0x100000 / 2
    add     t0, t0, TestAddr_1M
    lw      t1, (t0)
    lw      t0, (TestAddr_1M)
    li      t0, 0x100000 / 2
    add     t0, t0, TestAddr_1M
    lw      t1, (t0)

    /* @bug This should increment FinalDeviceID_1M, all 1MB RDRAMs are mapped to the same location */
    li      t0, 0x100000 << 6
    add     InitialDeviceID, InitialDeviceID, t0
    /* Increment RDRAM register base by 1x reg spacing */
    add     FinalRegBase_1M, FinalRegBase_1M, s0

    /* Increment test address */
    li      t0, 0x100000    /* 1MB */
    add     TestAddr_1M, TestAddr_1M, t0

    b       loop2_next
HM:
    /* 2MB Module */
    /* Set Device ID for first responder */
     sw     FinalDeviceID_2M, (RDRAM_DEVICE_ID_REG - RDRAM_BASE_REG)(s1)

    /* Write optimal CC value (auto) */
    addiu   s5, FinalRegBase_2M, (RDRAM_MODE_REG - RDRAM_BASE_REG)
    lw      a0, (sp) /* Reload CC value computed prior */
    addi    sp, sp, 8
    li      a1, CC_AUTO
    jal     WriteCC
     nop

    /* 8 reads */
    lw      t0, (TestAddr_2M)
    li      t0, 0x80000*1
    add     t0, t0, TestAddr_2M
    lw      t1, (t0)
    li      t0, 0x80000*2
    add     t0, t0, TestAddr_2M
    lw      t1, (t0)
    li      t0, 0x80000*3
    add     t0, t0, TestAddr_2M
    lw      t1, (t0)

    lw      t0, (TestAddr_2M)
    li      t0, 0x80000*1
    add     t0, t0, TestAddr_2M
    lw      t1, (t0)
    li      t0, 0x80000*2
    add     t0, t0, TestAddr_2M
    lw      t1, (t0)
    li      t0, 0x80000*3
    add     t0, t0, TestAddr_2M
    lw      t1, (t0)

    /* Increment Device ID by 2MB */
    li      t0, 0x200000 << 6
    add     FinalDeviceID_2M, FinalDeviceID_2M, t0

    /* Increment RDRAM reg base by 2x reg spacing */
    add     FinalRegBase_2M, FinalRegBase_2M, s0
    add     FinalRegBase_2M, FinalRegBase_2M, s0

    /* Increment test address */
    li      t0, 0x200000    /* 2MB */
    add     TestAddr_2M, TestAddr_2M, t0
loop2_next:
    /* Loop until all detected modules are configured */
    addiu   v1, v1, 1
    slt     t0, v1, NumModules
    bnez    t0, loop2
     nop

    /* Set RI_REFRESH */
    li      t2, PHYS_TO_K1(RI_BASE_REG)
    sll     ModuleBitmask_2M, ModuleBitmask_2M, 19
    li      t1, RI_REFRESH(0, 1, 1, 0, 54, 52)
    or      t1, t1, ModuleBitmask_2M                /* detected 2MB modules */
    sw      t1, (RI_REFRESH_REG - RI_BASE_REG)(t2)
    lw      t1, (RI_REFRESH_REG - RI_BASE_REG)(t2)  /* dummy read? */

    /* Save computed memory size */
#ifdef IPL3_X105
    li      t0, PHYS_TO_K1(0x000003F0)
    li      t1, 0xFFFFFFF
    and     TestAddr_1M, TestAddr_1M, t1
    sw      TestAddr_1M, (t0)
#else
    li      t0, PHYS_TO_K1(0x00000300)
    li      t1, 0xFFFFFFF
    and     TestAddr_1M, TestAddr_1M, t1
    sw      TestAddr_1M, 0x18(t0) /* osMemSize */
#endif

    move    sp, s8
    addiu   sp, sp, 0x48
    lw      s3, 0(sp)
    lw      s4, 4(sp)
    lw      s5, 8(sp)
    lw      s6, 0xC(sp)
    lw      s7, 0x10(sp)
    addiu   sp, sp, 0x18
.set reorder
    /* Initialize cache (cold reset) */

    la      t0, K0BASE
    addiu   t1, t0, ICACHE_SIZE
    addiu   t1, t1, -ICACHE_LINESIZE

    MTC0(   zero, C0_TAGLO)
    MTC0(   zero, C0_TAGHI)

    /* Index store tag icache */
1:
    CACHE(  CACH_PI | C_IST, t0)
.set noreorder
    bltu    t0, t1, 1b
     addiu  t0, t0, ICACHE_LINESIZE
.set reorder

    la      t0, K0BASE
    addiu   t1, t0, DCACHE_SIZE
    addiu   t1, t1, -DCACHE_LINESIZE

    /* index store tag dcache */
2:
    CACHE(  CACH_PD | C_IST, t0)
.set noreorder
    bltu    t0, t1, 2b
     addiu  t0, t0, DCACHE_LINESIZE

    b       load_ipl3
     nop
.set reorder

nmi:
    /* Initialize cache (nmi) */

    la      t0, K0BASE
    addiu   t1, t0, ICACHE_SIZE
    addiu   t1, t1, -ICACHE_LINESIZE

    MTC0(   zero, C0_TAGLO)
    MTC0(   zero, C0_TAGHI)

    /* index store tag icache */
1:
    CACHE(  CACH_PI | C_IST, t0)
.set noreorder
    bltu    t0, t1, 1b
     addiu  t0, t0, ICACHE_LINESIZE
.set reorder

    la      t0, K0BASE
    addiu   t1, t0, DCACHE_SIZE
    addiu   t1, t1, -DCACHE_LINESIZE

    /* index-writeback-invalidate dcache */
2:
    CACHE(  CACH_PD | C_IWBINV, t0)
.set noreorder
    bltu    t0, t1, 2b
     addiu  t0, t0, DCACHE_LINESIZE
.set reorder

load_ipl3:

#ifdef IPL3_X106
    mul     t4, s6, 0x260BCD5
    la      t2, PHYS_TO_K1(SP_DMEM_START)
    li      t3, 0xFFF00000
    li      t1, 0x100000
    and     t2, t2, t3
    la      t0, block17s
    addiu   t1, t1, -1
    and     t0, t0, t1
    la      t3, pifipl3e
    and     t3, t3, t1
    addiu   t4, t4, 1
    or      t0, t0, t2
    or      t3, t3, t2
    la      t1, K1BASE
send2:
    lw      t5, (t0)
    xor     t5, t5, t4
    mul     t4, t4, 0x260BCD5
    sw      t5, (t1)
    addiu   t0, t0, 4
    addiu   t1, t1, 4
    bltu    t0, t3, send2

    la      t4, K0BASE
    /* jump to RDRAM */
    jr      t4
    NOP
END(ipl3)

.set noreorder

/* This is encoded MIPS */
block17s:
.word 0x184A089E, 0x3E5EB772, 0x9D9FE9D2, 0xEAE6B59D, 0x7D834475, 0x215361F2, 0X390BD39E, 0x3D3261E1
.word 0x075D920A, 0xFB461E32, 0x2C6873FA, 0x41A07B32, 0x42536B48, 0xB89A636F, 0X2B57D91A, 0xB050EE82
.word 0x3CB87A0A, 0x199C7CD6, 0xB483C93A, 0xBEBB13E6, 0x93B3831A, 0x8C1F5F51, 0XC4C9235A, 0xC7CD1B4E
.word 0x3C0E25EA, 0x675D63B2, 0x5CAAAB1A, 0xCD6774A2, 0xE17B02CA, 0x9125AA12, 0X57FBB8FA, 0x62088002
.word 0xD3D3F9AA, 0xDE779272, 0xB7C890DA, 0x3A009D62, 0x42DD4EEA, 0xE9A57CC2, 0XC75312BB, 0x9148D332
.word 0xC30BB56A, 0x81BC7932, 0x250F1E92, 0x45588E02, 0x4E64126F, 0xCFB3F7B1, 0X8A5DF87D, 0x6DF0A8E7
.word 0xE4FD5933, 0xB1ACF812, 0x937E5446, 0x733D46F6, 0xA646F21A, 0x5255A277, 0XF8E87E1F, 0x702E1667
.word 0x8F01E4CA, 0x75965EA0, 0x3AD8321B, 0xB096FF87, 0xFE4F41EF, 0xB31A7D37, 0X77BA8FDF, 0x68CAD327
.word 0x1F44388F, 0x1E589D72, 0xAF86AFFB, 0x8BF61849, 0x805A9988, 0xE6E33FF7, 0X861B09BB, 0x4F12AFDD
.word 0x596ACC49, 0x7DF23434, 0xA44D959E, 0x17EF0107, 0xA8318161, 0x7B93AAB7, 0X7D2E735C, 0x8D2DC486
.word 0x7F87780B, 0xBC2E9AD4, 0x31AABB58, 0x5945C9C4, 0x19B4D12C, 0xA2E69556, 0XF1BA0D1C, 0xFAC32146
.word 0x2FE5DC02, 0x11D3D993, 0x58CE3903, 0x8DD2EAB0, 0xEB4298EB, 0x2A5C9012, 0XBECCE6E3, 0xA8310610
.word 0xC09FB78B, 0x0A1E2872, 0x12E35ECA, 0x4AB60364, 0x9774C88A, 0x825832C6, 0XAD2480B9, 0x244FB2C2
.word 0x4E473369, 0x433A9F32, 0x177ED365, 0xBE013422, 0xF600FC42, 0x2B75CD92, 0X435E426E, 0xD371E79E
.word 0xEFCA172C, 0x22351DD2, 0x8AF4A21B, 0x12D688E6, 0x3A94501A, 0x7ADE545A, 0X83AF2C3A, 0xFC5164E8
.word 0xBCFE4844, 0x441800B6, 0x4523C00A, 0xB31B4992, 0x1CA2AA9F, 0x52F49B1E, 0X662F997A, 0x839D291A
.word 0x3B4132FA, 0xE702337E, 0xF3FD21EA, 0x412E7E62, 0xE1AC778A, 0x4F9CCDD0, 0X658BD3DA, 0x25CB35D2
.word 0xB979926A, 0xD6FCC932, 0x81E1E442, 0x067EC732, 0x3CB1A74A, 0x887D8896, 0X0117D976, 0xA5B48A86
.word 0x5359B63E, 0x350DCEF2, 0xEC7D0959, 0x398FDFE2, 0x200B8F0A, 0x8EC0CB52, 0X309F6332, 0x04B78342
.word 0xF1A821EA, 0x2CED1FB2, 0x750D38E5, 0xDA67C0A6, 0x0F3BC134, 0x7CA069EE, 0X1FECB0FA, 0x08E51C02
.word 0xEEC565AA, 0x5A4EBE76, 0x3D71D324, 0xDFA7969E, 0x3066028A, 0x8C78FF0A, 0X9761FEBA, 0xDAC288C2
.word 0xB290A16A, 0xC396753A, 0x975C3ABA, 0x387B9201, 0x80A87642, 0xED28C392, 0X34089876
pifipl3e:
.word 0x00000000

.set reorder

#else /* IPL3_X106 */

#ifdef IPL3_X105
    li      t2, SP_SET_HALT | SP_CLR_BROKE | SP_CLR_INTR | SP_SET_SSTEP | SP_CLR_INTR_BREAK
    sw      t2, PHYS_TO_K1(SP_STATUS_REG)
#endif

    la      t2, PHYS_TO_K1(SP_DMEM_START)
    li      t3, 0xFFF00000
    li      t1, 0x100000
    and     t2, t2, t3
#ifdef IPL3_6101
    /* In the 6101 IPL3, these are physical addresses while in every other version they are KSEG1 addresses */
    la      t0, block17s-0xA0000000
    addiu   t1, t1, -1
    la      t3, pifipl3e-0xA0000000
#else
    la      t0, block17s
    addiu   t1, t1, -1
    la      t3, pifipl3e
#endif
    and     t0, t0, t1
    and     t3, t3, t1

#ifdef IPL3_X105
    /* reset RSP PC */
    sw      zero, PHYS_TO_K1(SP_PC_REG)
#endif

    or      t0, t0, t2
    or      t3, t3, t2
#ifdef IPL3_X105
    la      t1, PHYS_TO_K1(4)
#else
    la      t1, PHYS_TO_K1(0)
#endif

    /* copy the rest of IPL3 to RDRAM */
send2:
    lw      t5, (t0)
    sw      t5, (t1)
    addiu   t0, t0, 4
    addiu   t1, t1, 4
    bltu    t0, t3, send2

#ifdef IPL3_X105
    /* start the RSP */
    li      t2, SP_CLR_HALT | SP_CLR_BROKE | SP_CLR_INTR | SP_CLR_SSTEP | SP_CLR_INTR_BREAK
    sw      t2, PHYS_TO_K1(SP_STATUS_REG)
    la      t4, PHYS_TO_K0(0x00000004)
#else
    la      t4, PHYS_TO_K0(0x00000000)
#endif
    /* jump to RDRAM */
    jr      t4

block17s:
    /* the following was copied to RDRAM and jumped to */
    li      t3, PHYS_TO_K1(PI_DOM1_ADDR2)   /* cart base */
cart:
    li      t2, 0x1FFFFFFF
#ifdef IPL3_7102
    li      t1, PHYS_TO_K0(0x00000480)
#else
    lw      t1, 8(t3)
#endif
    and     t1, t1, t2
#ifdef IPL3_X103
    subu    t1, t1, 0x100000
#endif
    sw      t1, PHYS_TO_K1(PI_DRAM_ADDR_REG)

waitread:
    lw      t0, PHYS_TO_K1(PI_STATUS_REG)
    andi    t0, PI_STATUS_IO_BUSY
    bnez    t0, waitread

    li      t0, 0x1000
    add     t0, t0, t3
    and     t0, t0, t2
    sw      t0, PHYS_TO_K1(PI_CART_ADDR_REG)
    li      t2, 0x100000
#ifdef IPL3_X103
    addiu   t2, t2, 3
#else
    addiu   t2, t2, -1
#endif
    sw      t2, PHYS_TO_K1(PI_WR_LEN_REG)

waitdma:
#ifdef IPL3_6101
    NOP
    NOP
    NOP
    NOP
#endif
#if defined(IPL3_6101) || defined(IPL3_6102_7101)
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
#endif
#ifndef IPL3_X103
    NOP
    NOP
    NOP
    NOP
#endif
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    lw      t3, PHYS_TO_K1(PI_STATUS_REG)
    andi    t3, PI_STATUS_DMA_BUSY
    bnez    t3, waitdma

#ifdef IPL3_X105
    /* return the semaphore, notifies the RSP that PI DMA has completed */
    sw      zero, PHYS_TO_K1(SP_SEMAPHORE_REG)
#endif

    li      t3, PHYS_TO_K1(PI_DOM1_ADDR2)
    /* game entrypoint */
#ifndef IPL3_X103
.set noreorder
#endif
#ifdef IPL3_7102
    li      a0, PHYS_TO_K0(0x00000480)
#else
    lw      a0, 8(t3)
#endif
    move    a1, s6
#ifdef IPL3_X103
    subu    a0, a0, 0x100000
#else
.set reorder
#endif

    addiu   sp, sp, -0x20
    sw      ra, 0x1C(sp)
    sw      s0, 0x14(sp)
#ifdef IPL3_X105
    la      s6, PHYS_TO_K1(0x00000200)
#endif
    li      ra, 0x100000    /* 1MB */
    move    v1, zero
    move    t0, zero
    move    t1, a0

    mul     v0, a1, ROM_CHECKSUM_MAGIC
    addiu   v0, v0, 1
    move    a3, v0
    move    t2, v0
    move    t3, v0
    move    s0, v0
    move    a2, v0
    move    t4, v0
    li      t5, 32
checksum_loop:
    lw      v0, (t1)   /* rom data */
    addu    v1, a3, v0
    move    a1, v1
    bgeu    v1, a3, 1f
    addiu   t2, t2, 1
1:
    andi    v1, v0, 0x1F
    subu    t7, t5, v1
    srlv    t8, v0, t7
    sllv    t6, v0, v1
    or      a0, t6, t8
    move    a3, a1
    xor     t3, t3, v0
    addu    s0, s0, a0
    bgeu    a2, v0, 2f
    xor     t9, a3, v0
    xor     a2, t9, a2
    b       3f
2:
    xor     a2, a2, a0
3:
#ifdef IPL3_X105
    lw      t7, (s6) /* pifipl3e data below? */
    addiu   t0, t0, 4
    addiu   t1, t1, 4
    addiu   s6, s6, 4
    xor     t7, v0, t7
    addu    t4, t7, t4
    li      t7, PHYS_TO_K1(0x00000300) - 1
    and     s6, s6, t7
#else
    addiu   t0, t0, 4
    addiu   t1, t1, 4
    xor     t7, v0, s0
    addu    t4, t7, t4
#endif
    bne     t0, ra, checksum_loop

#ifndef IPL3_X105
.set noreorder
#endif
#ifdef IPL3_X103
    xor     t6, a3, t2
    addu    a3, t6, t3  /* Checksum 1 */
    xor     t8, s0, a2
    addu    s0, t8, t4  /* Checksum 2 */
#else
    xor     t6, a3, t2
    xor     a3, t6, t3  /* Checksum 1 */
    xor     t8, s0, a2
    xor     s0, t8, t4  /* Checksum 2 */
#endif
#ifndef IPL3_X105
.set reorder
#endif

#ifndef IPL3_X105
    li      t3, PHYS_TO_K1(PI_DOM1_ADDR2)
    lw      t0, 0x10(t3)
    bne     a3, t0, checksum_fail
    lw      t0, 0x14(t3)
    bne     s0, t0, checksum_fail
    bal     checksum_OK
checksum_fail:
    bal     checksum_fail
checksum_OK:
    /* Try to read PC, if the read worked the RSP is not running */
    lw      t1, PHYS_TO_K1(SP_PC_REG)
    lw      s0, 0x14(sp)
    lw      ra, 0x1C(sp)
    addiu   sp, sp, 0x20
    /* if the RSP PC is 0, skip */
    beqz    t1, 1f
    /* halt the RSP by forcing it into sstep mode? */
    li      t2, SP_SET_SSTEP | SP_CLR_HALT
    sw      t2, PHYS_TO_K1(SP_STATUS_REG)
    sw      zero, PHYS_TO_K1(SP_PC_REG)
1:
#endif

    li      t3, SP_SET_HALT | SP_CLR_BROKE | SP_CLR_INTR | SP_CLR_SSTEP | SP_CLR_INTR_BREAK | \
                SP_CLR_SIG0 | SP_CLR_SIG1 | SP_CLR_SIG2 | SP_CLR_SIG3 | SP_CLR_SIG4 | SP_CLR_SIG5 | SP_CLR_SIG6 | SP_CLR_SIG7
    sw      t3, PHYS_TO_K1(SP_STATUS_REG)

    li      t0, MI_INTR_MASK_CLR_SP | MI_INTR_MASK_CLR_SI | MI_INTR_MASK_CLR_AI | MI_INTR_MASK_CLR_VI | MI_INTR_MASK_CLR_PI | MI_INTR_MASK_CLR_DP; \
    sw      t0, PHYS_TO_K1(MI_INTR_MASK_REG)

    sw      zero, PHYS_TO_K1(SI_STATUS_REG)

    sw      zero, PHYS_TO_K1(AI_STATUS_REG)

    li      t1, MI_CLR_DP_INTR; \
    sw      t1, PHYS_TO_K1(MI_INIT_MODE_REG)

    li      t1, PI_CLR_INTR
    sw      t1, PHYS_TO_K1(PI_STATUS_REG); \
    li      t0, PHYS_TO_K1(0x00000300)
#if defined(IPL3_X103) || defined(IPL3_X105)
    li      t1, CIC_TYPE
    sw      t1, 0x10(t0)  /* osCicType */
    sw      s4, 0(t0)   /* osTvType */
    sw      s3, 4(t0)   /* osRomType */
    sw      s5, 0xC(t0)  /* osResetType */
    sw      s7, 0x14(t0)  /* osVersion */
#else
    sw      s7, 0x14(t0)  /* osVersion */
    sw      s5, 0xC(t0)  /* osResetType */
    sw      s3, 4(t0)   /* osRomType */
    sw      s4, 0(t0)   /* osTvType */
#endif

    beqz    s3, rom
    la      t1, PHYS_TO_K1(PI_DOM1_ADDR1)
    b       1f
rom:
    la      t1, PHYS_TO_K1(PI_DOM1_ADDR2)
1:
    sw      t1, 8(t0)       /* osRomBase */

#ifdef IPL3_X105
    lw      t1, 0xF0(t0)
    sw      t1, 0x18(t0)    /* osMemSize */
    li      t3, PHYS_TO_K1(PI_DOM1_ADDR2)
    lw      t0, 0x10(t3)
    bne     a3, t0, checksum_fail
    lw      t0, 0x14(t3)
    bne     s0, t0, checksum_fail
    bal     checksum_OK
checksum_fail:
    bal     checksum_fail
checksum_OK:
    la      t0, PHYS_TO_K1(SP_DMEM_START)
    lw      s0, 0x14(sp)
    lw      ra, 0x1c(sp)
    addiu   sp, sp, 0x20
    addi    t1, t0, SP_IMEM_END + 1 - SP_DMEM_START

del_spmem:
    sw      t1, (t0)
    addiu   t0, t0, 4
    bne     t0, t1, del_spmem

#else /* IPL3_X105 */
    la      t0, PHYS_TO_K1(SP_DMEM_START)
    addi    t1, t0, SP_DMEM_END + 1 - SP_DMEM_START

#ifdef IPL3_X103
    li      t2, -1
# define CLEAR_VAL t2
#else
# define CLEAR_VAL zero
#endif

del_dmem:
    sw      CLEAR_VAL, (t0)
    addiu   t0, t0, 4
    bne     t0, t1, del_dmem

    la      t0, PHYS_TO_K1(SP_IMEM_START)
    addi    t1, t0, SP_IMEM_END + 1 - SP_IMEM_START
del_imem:
    sw      CLEAR_VAL, (t0)
    addiu   t0, t0, 4
    bne     t0, t1, del_imem
#endif /* IPL3_X105 */

game:
#ifdef IPL3_X103
    la      t2, PHYS_TO_K1(SP_IMEM_START)
    li      t3, 6103
    sw      t3, (t2)
#endif
    /* Read cart entry point and jump to it */
    li      t3, PHYS_TO_K1(PI_DOM1_ADDR2)
#ifdef IPL3_7102
.set noreorder; .set reorder
    li      t1, PHYS_TO_K0(0x00000480)
#else
    lw      t1, 8(t3)
#endif
#ifdef IPL3_X103
.set noreorder; .set reorder
    subu    t1, t1, 0x100000
#endif
    jr      t1
#ifndef IPL3_X105
pifipl3e:
    NOP
#endif
END(ipl3)

#ifdef IPL3_X105
.set noreorder

/* This is RSP code */
                 /* start:                                      */
.word 0x40083800 /*     mfc0        $8, SP_SEMAPHORE            */ /* acquire the semaphore */
.word 0x400B0800 /*     mfc0        $11, SP_DRAM_ADDR           */
.word 0xC80C2000 /*     lqv         $v12[0], ($zero)            */
.word 0x8C040040 /*     lw          $4, 0x40($zero)             */
.word 0x00000000 /*     nop                                     */
.word 0x00000000 /*     nop                                     */
.word 0x40800000 /*     mtc0        $zero, SP_MEM_ADDR          */ /* DMA 8 bytes to DMEM offset 0 */
.word 0x38030180 /*     xori        $3, $zero, 0x180            */
.word 0x40830800 /*     mtc0        $3, SP_DRAM_ADDR            */
.word 0x40801000 /*     mtc0        $zero, SP_RD_LEN            */
.word 0x3C050020 /*     li          $5, 0x200000                */ /* wait until PI DMA is done, skip to the end if it times out */
                 /* acquire_semaphore:                          */
.word 0x04A0001B /*     bltz        $5, end                     */
.word 0x40033800 /*      mfc0       $3, SP_SEMAPHORE            */
.word 0x1460FFFD /*     bnez        $3, acquire_semaphore       */
.word 0x20A5FFFF /*      addi       $5, $5, -1                  */
.word 0x8C060000 /*     lw          $6, ($zero)                 */ /* prepare $6 */
.word 0x40800000 /*     mtc0        $zero, SP_MEM_ADDR          */ /* DMA 0x1000 bytes of DRAM at 0x400 to DMEM at 0 */
.word 0x38030400 /*     xori        $3, $zero, 0x400            */
.word 0x40830800 /*     mtc0        $3, SP_DRAM_ADDR            */
.word 0x38030FFF /*     xori        $3, $zero, 0xFFF            */
.word 0x40831000 /*     mtc0        $3, SP_RD_LEN               */
                 /* dma_wait:                                   */ /* wait for DMA */
.word 0x40033000 /*     mfc0        $3, SP_DMA_BUSY             */
.word 0x1460FFFE /*     bnez        $3, dma_wait                */
.word 0x38030FF0 /*      xori       $3, $zero, 0xFF0            */
.word 0x4A0D6B51 /*     vsub        $v13, $v13, $v13            */ /* clear $v13 */
                 /* sum:                                        */ /* sum the contents of DMEM via vaddc, from top to bottom */
.word 0xC86E2000 /*     lqv         $v14[0], ($3)               */
.word 0x2063FFF0 /*     addi        $3, $3, -0x10               */
.word 0x0461FFFD /*     bgez        $3, sum                     */
.word 0x4A0E6B54 /*      vaddc      $v13, $v13, $v14            */
.word 0x3803B120 /*     xori        $3, $zero, 0xB120           */
.word 0x40830000 /*     mtc0        $3, SP_MEM_ADDR             */ /* 0xB120 -> 0x1120 (13 bits) */
.word 0x3C03B12F /*     lui         $3, 0xB12F                  */
.word 0x3863B1F0 /*     xori        $3, $3, 0xB1F0              */
.word 0x40830800 /*     mtc0        $3, SP_DRAM_ADDR            */ /* 0xB12FB1F0 -> 0x2FB1F0 (24 bits) */
.word 0x3C03FE81 /*     lui         $3, 0xFE81                  */
.word 0x38637000 /*     xori        $3, $3, 0x7000              */
.word 0x40831800 /*     mtc0        $3, SP_WR_LEN               */ /* 0xFE817000 -> Skip=0xFE8 Count=23 Length=0 (8 bytes) */
.word 0x38030240 /*     xori        $3, $zero, 0x240            */ /* DPC_CLR_CLOCK_CTR | DPC_CLR_TMEM_CTR */
.word 0x40835800 /*     mtc0        $3, DPC_STATUS              */
                 /* end:                                        */
.word 0x0000000D /*     break       0                           */ /* halt */
.word 0x00000000 /*     nop                                     */
.word 0x00000000 /*     nop                                     */

.set reorder
#endif

#endif /* IPL3_X106 */

/**
 *  Find and set RDRAM Current Control (CC) value
 *
 *  Return (v0) : Calibrated CC value
 */
LEAF(InitCCValue)
    addiu   sp, sp, -0xA0
    sw      s0, 0x40(sp)
    sw      s1, 0x44(sp)
#ifdef IPL3_X105
pifipl3e:
#endif
    move    s1, zero
    move    s0, zero
    sw      v0, 0x00(sp)
    sw      v1, 0x04(sp)
    sw      a0, 0x08(sp)
    sw      a1, 0x0C(sp)
    sw      a2, 0x10(sp)
    sw      a3, 0x14(sp)
    sw      t0, 0x18(sp)
    sw      t1, 0x1C(sp)
    sw      t2, 0x20(sp)
    sw      t3, 0x24(sp)
    sw      t4, 0x28(sp)
    sw      t5, 0x2C(sp)
    sw      t6, 0x30(sp)
    sw      t7, 0x34(sp)
    sw      t8, 0x38(sp)
    sw      t9, 0x3C(sp)
    sw      s2, 0x48(sp)
    sw      s3, 0x4C(sp)
    sw      s4, 0x50(sp)
    sw      s5, 0x54(sp)
    sw      s6, 0x58(sp)
    sw      s7, 0x5C(sp)
    sw      s8, 0x60(sp)
    sw      ra, 0x64(sp)

    /* Compute the CC value four times, sum for average */
CCloop1:
    jal     FindCC
    addu    s1, s1, v0  /* s1 += cc */
    addiu   s0, s0, 1
    slti    t1, s0, 4
    bnez    t1, CCloop1 /* while (s0 < 4) */

    /* Write the average CC value */
    srl     a0, s1, 2   /* a0 = s1 / 4 */
    li      a1, CC_AUTO
    jal     WriteCC

    /* Return the average CC value in v0 */
    srl     v0, s1, 2

    lw      s1, 0x44(sp)
    lw      v1, 0x04(sp)
    lw      a0, 0x08(sp)
    lw      a1, 0x0C(sp)
    lw      a2, 0x10(sp)
    lw      a3, 0x14(sp)
    lw      t0, 0x18(sp)
    lw      t1, 0x1C(sp)
    lw      t2, 0x20(sp)
    lw      t3, 0x24(sp)
    lw      t4, 0x28(sp)
    lw      t5, 0x2C(sp)
    lw      t6, 0x30(sp)
    lw      t7, 0x34(sp)
    lw      t8, 0x38(sp)
    lw      t9, 0x3C(sp)
    lw      s0, 0x40(sp)
    lw      s2, 0x48(sp)
    lw      s3, 0x4C(sp)
    lw      s4, 0x50(sp)
    lw      s5, 0x54(sp)
    lw      s6, 0x58(sp)
    lw      s7, 0x5C(sp)
    lw      s8, 0x60(sp)
    lw      ra, 0x64(sp)
    addiu   sp, sp, 0xA0
    jr      ra
END(InitCCValue)

/**
 * Tests various CC values until it finds the best value passing TestCCValue.
 * Once found, converts the "Manual" CC value to an "Automatic" CC value and returns it in v0.
 */
LEAF(FindCC)
    addiu   sp, sp, -0x20
    sw      ra, 0x1C(sp)
    move    t1, zero
    move    t3, zero
    move    t4, zero
prepass_loop:
    /* Stop searching if nominal CC value >= 64 */
    slti    k0, t4, 64
    beqz    k0, done_findcc

    /* Test this RDRAM module with the current CC value */
    move    a0, t4
    jal     TestCCValue

    blez    v0, next_pass

    /* CC test successful */
    subu    k0, v0, t1
    mul     k0, k0, t4
    addu    t3, t3, k0      /* t3 += (v0 - t1) * t4  */
    move    t1, v0          /* t1 = v0 */
next_pass:
    addiu   t4, t4, 1
    slti    k0, t1, 80
    bnez    k0, prepass_loop    /* while (t1 < 80) */

    mul     a0, t3, 22
    addiu   a0, a0, -(22 * 40)
    /* a0 = (t3 - 40) * 22 */
    jal     ConvertManualToAuto

    b       return_findcc

done_findcc:
    move    v0, zero    /* Failed to find a working CC value, return 0 */
return_findcc:
    lw      ra, 0x1C(sp)
    addiu   sp, sp, 0x20
    jr      ra
END(FindCC)

/*
 * Tests the operation of RDRAM with a particular CC value
 *
 *  a0 = CC value to test
 *
 *  s4 = RDRAM address to use for testing
 */
LEAF(TestCCValue)
    addiu   sp, sp, -0x28
    sw      ra, 0x1C(sp)

    move    v0, zero
    /* Write in the CC value (manual) */
    li      a1, CC_MANUAL
    jal     WriteCC

    move    s8, zero
jloop:
    /* write -1 */
    li      k0, -1
    sw      k0, 0(s4)
    sw      k0, 0(s4)
    sw      k0, 4(s4)
    /* read back */
    lw      v1, 4(s4)
    srl     v1, v1, 16

    /* Count the number of bits set in bits [23:16] of the read value */
    move    gp, zero
kloop:
    andi    k0, v1, 1
    beqz    k0, no_passcount
    /* Increment counter if the bit is still set */
    addiu   v0, v0, 1
no_passcount:
    srl     v1, v1, 1
    addiu   gp, gp, 1
    slti    k0, gp, 8
    bnez    k0, kloop   /* while (gp < 8) */

    addiu   s8, s8, 1
    slti    k0, s8, 10
    bnez    k0, jloop   /* while (s8 < 10) */

    /* v0 = 10 * 8 = 80 if all tests passed */

    lw      ra, 0x1C(sp)
    addiu   sp, sp, 0x28
    jr      ra
END(TestCCValue)

/*
 *  Converts a manual CC value to an appropriate auto CC value, since
 *  manual CC value testing is done with manual setting but it should
 *  run with automatic setting.
 *
 *  a0 = manual CC value?
 *  v0 = auto CC value
 */
LEAF(ConvertManualToAuto)
    addiu   sp, sp, -0x28
    sw      ra, 0x1C(sp)
    sw      a0, 0x20(sp)
    sb      zero, 0x27(sp)
    move    t0, zero
    move    t2, zero
    li      t5, 64 * 800
    move    t6, zero
big_loop:
    slti    k0, t6, 64
    bnez    k0, coverloop   /* skip if (t6 < 64) */
    move    v0, zero
    b       convert_done    /* return 0 */
coverloop:
    move    a0, t6
    li      a1, CC_AUTO
    jal     WriteCC

    /* Read CC (twice? supposedly some NEC chips need to do this to ensure the read worked) */
    addiu   a0, sp, 0x27
    jal     ReadCC
    addiu   a0, sp, 0x27
    jal     ReadCC
    lbu     k0, 0x27(sp)

    /* Multiply by 800 */
    li      k1, 800
    mul     t0, k0, k1

    lw      a0, 0x20(sp)
    subu    k0, t0, a0
    bgez    k0, pos
    subu    k0, a0, t0
pos:
    /* k0 = ABS(a0 - t0) */

    slt     k1, k0, t5
    beqz    k1, compare_done    /* branch if k0 >= t5 */
    move    t5, k0
    move    t2, t6
compare_done:
    lw      a0, 0x20(sp)
    slt     k1, t0, a0
    beqz    k1, return_value    /* break out of loop if t0 >= a0 */

    addiu   t6, t6, 1
    slti    k1, t6, 65
    bnez    k1, big_loop        /* while (t6 < 65) */

return_value:
    addu    v0, t2, t6
    srl     v0, v0, 1
    /* return (t2 + t6) / 2 */
convert_done:
    lw      ra, 0x1C(sp)
    addiu   sp, sp, 0x28
    jr      ra
END(ConvertManualToAuto)

/*
 * Write CC value and auto to RDRAM_MODE register
 *
 *  a0 = CC value ({ C5, C4, C3, C2, C1, C0 })
 *  a1 = auto if 1, manual otherwise
 *  s5 = PHYS_TO_K1(RDRAM_MODE_REG)
 */
LEAF(WriteCC)
    addiu   sp, sp, -0x28
    andi    a0, a0, 0xff
    xori    a0, a0, 0x3f        /* There are 6 CC bits */
    sw      ra, 0x1C(sp)
    li      t7, RDRAM_MODE_CC_MULT | RDRAM_MODE_AUTO_SKIP | RDRAM_MODE_DEVICE_ENABLE
    li      k1, CC_AUTO
    bne     a1, k1, non_auto
    /* Auto, set CE bit */
    li      k0, RDRAM_MODE_CC_ENABLE
    or      t7, t7, k0
non_auto:
    /* Get the CC bits from a0 */
    andi    k0, a0, 1
    sll     k0, k0, 6
    or      t7, t7, k0  /* t7 |= (a0 & 0x01 <<  6) */
    andi    k0, a0, 2
    sll     k0, k0, 13
    or      t7, t7, k0  /* t7 |= (a0 & 0x02 << 13) */
    andi    k0, a0, 4
    sll     k0, k0, 20
    or      t7, t7, k0  /* t7 |= (a0 & 0x04 << 20) */
    andi    k0, a0, 8
    sll     k0, k0, 4
    or      t7, t7, k0  /* t7 |= (a0 & 0x08 <<  4) */
    andi    k0, a0, 16
    sll     k0, k0, 11
    or      t7, t7, k0  /* t7 |= (a0 & 0x10 << 11) */
    andi    k0, a0, 32
    sll     k0, k0, 18
    or      t7, t7, k0  /* t7 |= (a0 & 0x20 << 18) */
    /* Write new RDRAM_MODE value */
    sw      t7, (s5)
    li      k1, CC_AUTO
    bne     a1, k1, write_done
    /* If auto, also write 0 to MI_INIT_MODE (clears init length?) */
    li      k0, PHYS_TO_K1(MI_INIT_MODE_REG)
    sw      zero, (k0)
write_done:
    lw      ra, 0x1C(sp)
    addiu   sp, sp, 0x28
    jr      ra
END(WriteCC)

/*
 * Read CC value from RDRAM_MODE register
 *
 *  a0 = where to store read value
 *  s5 = PHYS_TO_K1(RDRAM_MODE_REG)
 */
LEAF(ReadCC)
    addiu   sp, sp, -0x28
    sw      ra, 0x1C(sp)
    li      k0, MI_SET_RDRAM
    li      k1, PHYS_TO_K1(MI_INIT_MODE_REG)
    sw      k0, (k1)
    move    s8, zero
    /* Read RDRAM_MODE */
    lw      s8, (s5)
    li      k0, MI_CLR_RDRAM
    sw      k0, (k1)
    /* Extract CC bits */
    li      k1, 0x40
    and     k1, k1, s8
    srl     k1, k1, 6
    move    k0, zero
    or      k0, k0, k1  /* k0 |= (s8 & 0x000040 >>  6) */
    li      k1, 0x4000
    and     k1, k1, s8
    srl     k1, k1, 13
    or      k0, k0, k1  /* k0 |= (s8 & 0x004000 >> 13) */
    li      k1, 0x400000
    and     k1, k1, s8
    srl     k1, k1, 20
    or      k0, k0, k1  /* k0 |= (s8 & 0x400000 >> 20) */
    li      k1, 0x80
    and     k1, k1, s8
    srl     k1, k1, 4
    or      k0, k0, k1  /* k0 |= (s8 & 0x000080 >>  4) */
    li      k1, 0x8000
    and     k1, k1, s8
    srl     k1, k1, 11
    or      k0, k0, k1  /* k0 |= (s8 & 0x008000 >> 11) */
    li      k1, 0x800000
    and     k1, k1, s8
    srl     k1, k1, 18
    or      k0, k0, k1  /* k0 |= (s8 & 0x800000 >> 18) */
    /* Store CC value */
    sb      k0, (a0)
    lw      ra, 0x1C(sp)
    addiu   sp, sp, 0x28
    jr      ra
END(ReadCC)

.set noreorder

#if defined(IPL3_X103)
.word 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x09000419, 0x20010FC0, 0x8C220010, 0x20030F7F
.word 0x20071080, 0x40870000, 0x40820800, 0x40831000, 0x40043000, 0x1480FFFE, 0x00000000, 0x0D00040F
.word 0x00000000, 0x00E00008, 0x40803800, 0x40082000, 0x31080080, 0x15000002, 0x00000000, 0x03E00008
.word 0x40803800, 0x34085200, 0x40882000, 0x0000000D, 0x00000000, 0x8C220004, 0x30420002, 0x10400007
.word 0x00000000, 0x0D00040F, 0x00000000, 0x40025800, 0x30420100, 0x1C40FFED, 0x00000000, 0x8C220018
.word 0x8C23001C, 0x2063FFFF, 0x401E2800, 0x17C0FFFE, 0x00000000, 0x40800000, 0x40820800, 0x40831000
.word 0x40043000, 0x1480FFFE, 0x00000000, 0x0D00040F, 0x00000000, 0x09000402, 0x00000000, 0x02001001
.word 0x400A0088, 0x04402202, 0x081041FF, 0x08084044, 0x0120087F, 0x02041010, 0x80840420, 0x41FE0808
.word 0x40220110, 0x08804404, 0x3FC00700, 0xC6080880, 0x24014002, 0x00100080, 0x02009004, 0x40418C03
.word 0x807E020C, 0x10108044, 0x02200900, 0x48024012, 0x01100880, 0x84183F00, 0x7FE20010, 0x00800400
.word 0x2001FF08, 0x00400200, 0x10008004, 0x003FF07F, 0xE2001000, 0x80040020, 0x01FF0800, 0x40020010
.word 0x00800400, 0x20000700, 0xC6080880, 0x24014002, 0x00100083, 0xF2009004, 0x40618D03, 0x88401200
.word 0x90048024, 0x012009FF, 0xC8024012, 0x00900480, 0x24012008, 0x07001000, 0x80040020, 0x01000800
.word 0x40020010, 0x00800400, 0x20038000, 0x40020010, 0x00800400, 0x20010008, 0x00420210, 0x10808208
.word 0x0F804022, 0x02102082, 0x04202201, 0x200A8062, 0x02081020, 0x80840220, 0x08400200, 0x10008004
.word 0x00200100, 0x08004002, 0x00100080, 0x04003FF0, 0x800C0070, 0x07405A02, 0xC8264131, 0x11888C28
.word 0x61430418, 0x20C00440, 0x23011408, 0xA0448222, 0x11108844, 0x42220910, 0x28814406, 0x20100F01
.word 0x86100880, 0x4801400A, 0x00500280, 0x14009008, 0x80430C07, 0x807F8202, 0x10088044, 0x02201101
.word 0x0FF04002, 0x00100080, 0x04002000, 0x0F018610, 0x08804801, 0x400A0050, 0x02801410, 0x90488143
.word 0x0C07907F, 0x82021008, 0x80440220, 0x21FE0820, 0x40820410, 0x10808402, 0x20101F81, 0x02100880
.word 0x44001000, 0x70007000, 0x40011008, 0x8042040F, 0xC07FF010, 0x00800400, 0x20010008, 0x00400200
.word 0x10008004, 0x00200100, 0x40220110, 0x08804402, 0x20110088, 0x04402201, 0x08104081, 0x08078040
.word 0x12008808, 0x40420208, 0x20410110, 0x08804401, 0x400A0020, 0x0100820C, 0x1060828A, 0x24512289
.word 0x14451428, 0xA1450A28, 0x20810408, 0x20401101, 0x04102080, 0x88028008, 0x00400500, 0x44041020
.word 0x82022008, 0x40110108, 0x08208088, 0x04401400, 0x40020010, 0x00800400, 0x2001007F, 0xE0010010
.word 0x01000800, 0x80080080, 0x08008004, 0x00400400, 0x3FF00F80, 0x82080840, 0x42021010, 0x80840420
.word 0x21010808, 0x40410407, 0xC0020030, 0x02800400, 0x20010008, 0x00400200, 0x10008004, 0x00200100
.word 0x0F008408, 0x10408004, 0x00200200, 0x20020020, 0x02002002, 0x001FE00F, 0x00840810, 0x40800400
.word 0x401C0010, 0x00400208, 0x10408108, 0x07800100, 0x1800C00A, 0x00900480, 0x44042021, 0x02081FF8
.word 0x02001000, 0x801F8100, 0x08004002, 0x001780C2, 0x04080040, 0x02081040, 0x81080780, 0x0F008408
.word 0x10408200, 0x1000BC06, 0x10204102, 0x08104081, 0x0807803F, 0xC0020020, 0x01001000, 0x80040040
.word 0x02001001, 0x00080040, 0x02000F00, 0x84081040, 0x82040840, 0x3C021020, 0x41020810, 0x40810807
.word 0x800F0084, 0x08104082, 0x04102043, 0x01E80040, 0x02081040, 0x81080780, 0x02001000, 0x80040020
.word 0x01000800, 0x40020010, 0x00000000, 0x200100D8, 0x06C01201, 0x20000000, 0x00000000, 0x00000000
.word 0x00000000, 0x00000440, 0x22011008, 0x87FF0440, 0x22011008, 0x83FF8440, 0x22011008, 0x80C00600
.word 0x10010000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x80444124, 0x05401C00
.word 0x40070054, 0x04904440, 0x20000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
#elif defined(IPL3_X105)
.word 0x401C3000, 0x1780FFFE, 0x3801B120, 0x40810000, 0x40083800, 0x400B0800, 0x400A6000, 0x8C040040
.word 0x3C1EB12F, 0x3BDEB1F0, 0x409E0800, 0x3C03FE81, 0x38637000, 0x40831800, 0x38090240, 0x40895800
.word 0x3C057FFF, 0x34A50000, 0x04A00003, 0x40063800, 0x10C00001, 0x20A5FFFF, 0x0000000D, 0x00000000
.word 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
.word 0xFFC67E81, 0x6B4BFBE2, 0xFB54F6BD, 0xDF7C1CE1, 0x8701BF31, 0xDE56720F, 0x47676687, 0x59AA883C
.word 0x59EA5613, 0x7BD285A1, 0xD83C5455, 0x2F37AE65, 0x5BDA0279, 0x98CCE31A, 0x768E5FD9, 0x998F1F3F
.word 0x36EE4378, 0x4D0DFABE, 0xA6DAE486, 0x8EDC296D, 0x4EFF56E1, 0x7020FB8F, 0xB1580590, 0xC509DC53
.word 0xCDAA3B48, 0x9952D352, 0x9D069FEA, 0xB5C20613, 0x9849B201, 0x1EAC3288, 0x319C5246, 0x9571368F
.word 0x57F6391D, 0x16FA8874, 0xF5987C17, 0x5C41BB6D, 0x718E0F70, 0x59C7011B, 0x2F333D91, 0xC01DA50D
.word 0x0DAB338D, 0x7E5E8F3E, 0xE66874A6, 0x3AB1C393, 0x11A864C7, 0xDBCAE060, 0xE1F3BF09, 0x0067A2E3
.word 0x25A02131, 0x87D562C5, 0xA84F7E2E, 0x096B949F, 0xB06DA99E, 0x5A0B4670, 0x80B6CF47, 0x0CA6A52A
.word 0xD8ACFBA0, 0xEBB77924, 0x72239248, 0x80C5A6A7, 0x85B7D78C, 0x90E4AB63, 0x445266E3, 0x9C3325F9
.word 0x5EAABA73, 0x605D4B71, 0x7EBEA98C, 0x571971C3, 0xCA5EE52A, 0x33AC8851, 0x66A17B75, 0x67649A69
.word 0xEF6F5642, 0xA01D51C5, 0x02F7BB92, 0x45BE6F0D, 0xB638CC10, 0xFDBB5451, 0x1C7B0794, 0x27937D92
.word 0xC3D4C6A5, 0x61510138, 0x38A7BFF1, 0x040D159B, 0x801F83D5, 0xA469887C, 0x9FB601DA, 0x9317458B
.word 0x12B20233, 0x5C50D6E1, 0x56A4AD42, 0x4A5CDD86, 0x61E90312, 0xE10F9BEA, 0x262C61DC, 0x62486B6D
.word 0x14E00385, 0x4A7246DA, 0x96C87D1C, 0xD1053EE5, 0x9270435F, 0x6C0305B3, 0xEBB32035, 0x4D7E6650
.word 0x0136C033, 0xE10FC938, 0x2EE92919, 0x4F5EB1D1, 0x498B3B53, 0xFD9F3FEE, 0x2525357B, 0x0D11AF4C
.word 0x118C32D4, 0xDA7FD816, 0x57E1A6CE, 0x7DC1AE62, 0xBF13E487, 0x4C3AC1B3, 0x0C599947, 0x585ABD78
.word 0x7CBA5001, 0xED1BEA8A, 0x4988EED6, 0x1485ABB0, 0x2CDE3593, 0x112D011C, 0xD7284330, 0xE7B008ED
.word 0x79991351, 0xD23A77AD, 0x3DB4F8C7, 0xCA0322D2, 0xC9C6270F, 0x04CE7A3F, 0xC0682CCF, 0x726A09C2
.word 0x4200725E, 0x4134F896, 0x693FBD3A, 0x58918BE1, 0xCCA2B192, 0xDD77A135, 0xFEF34BBC, 0xB1E33711
.word 0x0DC765BE, 0xF161E55E, 0x06FF35C7, 0x76895DF4, 0x6E4ACCB5, 0x547EF115, 0xC8A0998F, 0x5C700BEF
.word 0x14C6E50A, 0x9C19B41D, 0x4CCE5606, 0xDC421125, 0xE7966F0F, 0x213DDFF9, 0x57470DDF, 0x2B6AFC77
.word 0x8DD5E9D9, 0xF9B5E0EB, 0x72841A8E, 0x42141D8A, 0x6E5F923A, 0xFB0BE5F6, 0xE4C09F45, 0xD62A83BF
.word 0xB1CD6AC4, 0xBF8CDEDF, 0xB2F779F7, 0x6057FC3B, 0x3D7B2ECB, 0x9C417B27, 0xA5E34858, 0x150717E0
.word 0xB9855F63, 0xA8F62912, 0x43006ADB, 0xEE642452, 0x8BC43B5D, 0xBB3518A2, 0xD389FFB2, 0xA05930F2
.word 0xDBD5C14D, 0x6A4B369C, 0x5D78E6D0, 0xA3920DE5, 0x9011B086, 0x0F413480, 0xA689BDE9, 0x2F78470D
.word 0x00000000, 0x00000000, 0x00000000, 0x00000000
#elif defined(IPL3_X106)
.word 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
.word 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
.word 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
.word 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
.word 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
.word 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
.word 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
.word 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
.word 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
.word 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
.word 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
.word 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
.word 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
.word 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
.word 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
.word 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
.word 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
.word 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
.word 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
.word 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
.word 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
.word 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
.word 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
.word 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
.word 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
.word 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
.word 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
.word 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
.word 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
.word 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
.word 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
.word 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
.word 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
.word 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
.word 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
#else
#if defined(IPL3_6102_7101)
.word 0x00000000
#elif defined(IPL3_7102)
.word 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
.word 0x00000000, 0x00000000
#endif
.word 0x02001001, 0x400A0088, 0x04402202, 0x081041FF, 0x08084044, 0x0120087F, 0x02041010, 0x80840420
.word 0x41FE0808, 0x40220110, 0x08804404, 0x3FC00700, 0xC6080880, 0x24014002, 0x00100080, 0x02009004
.word 0x40418C03, 0x807E020C, 0x10108044, 0x02200900, 0x48024012, 0x01100880, 0x84183F00, 0x7FE20010
.word 0x00800400, 0x2001FF08, 0x00400200, 0x10008004, 0x003FF07F, 0xE2001000, 0x80040020, 0x01FF0800
.word 0x40020010, 0x00800400, 0x20000700, 0xC6080880, 0x24014002, 0x00100083, 0xF2009004, 0x40618D03
.word 0x88401200, 0x90048024, 0x012009FF, 0xC8024012, 0x00900480, 0x24012008, 0x07001000, 0x80040020
.word 0x01000800, 0x40020010, 0x00800400, 0x20038000, 0x40020010, 0x00800400, 0x20010008, 0x00420210
.word 0x10808208, 0x0F804022, 0x02102082, 0x04202201, 0x200A8062, 0x02081020, 0x80840220, 0x08400200
.word 0x10008004, 0x00200100, 0x08004002, 0x00100080, 0x04003FF0, 0x800C0070, 0x07405A02, 0xC8264131
.word 0x11888C28, 0x61430418, 0x20C00440, 0x23011408, 0xA0448222, 0x11108844, 0x42220910, 0x28814406
.word 0x20100F01, 0x86100880, 0x4801400A, 0x00500280, 0x14009008, 0x80430C07, 0x807F8202, 0x10088044
.word 0x02201101, 0x0FF04002, 0x00100080, 0x04002000, 0x0F018610, 0x08804801, 0x400A0050, 0x02801410
.word 0x90488143, 0x0C07907F, 0x82021008, 0x80440220, 0x21FE0820, 0x40820410, 0x10808402, 0x20101F81
.word 0x02100880, 0x44001000, 0x70007000, 0x40011008, 0x8042040F, 0xC07FF010, 0x00800400, 0x20010008
.word 0x00400200, 0x10008004, 0x00200100, 0x40220110, 0x08804402, 0x20110088, 0x04402201, 0x08104081
.word 0x08078040, 0x12008808, 0x40420208, 0x20410110, 0x08804401, 0x400A0020, 0x0100820C, 0x1060828A
.word 0x24512289, 0x14451428, 0xA1450A28, 0x20810408, 0x20401101, 0x04102080, 0x88028008, 0x00400500
.word 0x44041020, 0x82022008, 0x40110108, 0x08208088, 0x04401400, 0x40020010, 0x00800400, 0x2001007F
.word 0xE0010010, 0x01000800, 0x80080080, 0x08008004, 0x00400400, 0x3FF00F80, 0x82080840, 0x42021010
.word 0x80840420, 0x21010808, 0x40410407, 0xC0020030, 0x02800400, 0x20010008, 0x00400200, 0x10008004
.word 0x00200100, 0x0F008408, 0x10408004, 0x00200200, 0x20020020, 0x02002002, 0x001FE00F, 0x00840810
.word 0x40800400, 0x401C0010, 0x00400208, 0x10408108, 0x07800100, 0x1800C00A, 0x00900480, 0x44042021
.word 0x02081FF8, 0x02001000, 0x801F8100, 0x08004002, 0x001780C2, 0x04080040, 0x02081040, 0x81080780
.word 0x0F008408, 0x10408200, 0x1000BC06, 0x10204102, 0x08104081, 0x0807803F, 0xC0020020, 0x01001000
.word 0x80040040, 0x02001001, 0x00080040, 0x02000F00, 0x84081040, 0x82040840, 0x3C021020, 0x41020810
.word 0x40810807, 0x800F0084, 0x08104082, 0x04102043, 0x01E80040, 0x02081040, 0x81080780, 0x02001000
.word 0x80040020, 0x01000800, 0x40020010, 0x00000000, 0x200100D8, 0x06C01201, 0x20000000, 0x00000000
.word 0x00000000, 0x00000000, 0x00000440, 0x22011008, 0x87FF0440, 0x22011008, 0x83FF8440, 0x22011008
.word 0x80C00600, 0x10010000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x80444124
.word 0x05401C00, 0x40070054, 0x04904440, 0x20000000, 0x00000080, 0x04002001, 0x00080FFE, 0x02001000
.word 0x80040020, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00003001, 0x80040040, 0x00000000
.word 0x00000000, 0x00000000, 0x0FFE0000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000
.word 0x00000000, 0x30018000, 0x00000000, 0x00004004, 0x00400400, 0x40040040, 0x04004004, 0x00400400
.word 0x40000000, 0x0000000C, 0x00600000, 0x00000000, 0x00000180, 0x0C000000, 0x00000000, 0x00000000
.word 0x003FF800, 0x00000003, 0xFF800000, 0x00000000, 0x07004404, 0x10208004, 0x00400400, 0x40020010
.word 0x00000000, 0x20010007, 0x00C60808, 0x80243142, 0x4A225122, 0x89223610, 0x02402186, 0x03C00000
.word 0x00000000, 0x00000000, 0x00000000, 0x00000000
#endif
