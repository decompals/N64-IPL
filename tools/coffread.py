#!/usr/bin/env python3
#
#   ECOFF Object Files Reader and Disassembler
#

import struct
from mdebug import EcoffHDRR, EcoffFdr, EcoffSt

"""
ECOFF Magic Number
"""

MAGIC_ARCH_MASK   = 0x00FF
MAGIC_ARCH_SHFT   = 0
MAGIC_S_ARCH_MASK = 0xFF00
MAGIC_S_ARCH_SHFT = 8

MIPSEBMAGIC       = 0x0160
MIPSELMAGIC       = 0x0162
SMIPSEBMAGIC      = 0x6001
SMIPSELMAGIC      = 0x6201
MIPSEBUMAGIC      = 0x0180
MIPSELUMAGIC      = 0x0182
MIPSEBMAGIC_2     = 0x0163
MIPSELMAGIC_2     = 0x0166
SMIPSEBMAGIC_2    = 0x6301
SMIPSELMAGIC_2    = 0x6601
MIPSEBMAGIC_3     = 0x0140
MIPSELMAGIC_3     = 0x0142
SMIPSEBMAGIC_3    = 0x4001
SMIPSELMAGIC_3    = 0x4201
MAGIC_MIPS1       = 0x0062
MAGIC_MIPS2       = 0x0066
MAGIC_MIPS3       = 0x0042

ECOFF_MAGIC_NAMES = {
    MIPSEBMAGIC    : "MIPSEB",
    MIPSELMAGIC    : "MIPSEL",
    SMIPSEBMAGIC   : "SMIPSEB",
    SMIPSELMAGIC   : "SMIPSEL",
    MIPSEBUMAGIC   : "MIPSEBU",
    MIPSELUMAGIC   : "MIPSELU",
    MIPSEBMAGIC_2  : "MIPSEB_2",
    MIPSELMAGIC_2  : "MIPSEL_2",
    SMIPSEBMAGIC_2 : "SMIPSEB_2",
    SMIPSELMAGIC_2 : "SMIPSEL_2",
    MIPSEBMAGIC_3  : "MIPSEB_3",
    MIPSELMAGIC_3  : "MIPSEL_3",
    SMIPSEBMAGIC_3 : "SMIPSEB_3",
    SMIPSELMAGIC_3 : "SMIPSEL_3",
    MAGIC_MIPS1    : "MIPS1",
    MAGIC_MIPS2    : "MIPS2",
    MAGIC_MIPS3    : "MIPS3",
}

"""
ECOFF Header Flags
"""

F_RELFLG           = 0x0000001  # relocation info stripped from file
F_EXEC             = 0x0000002  # file is executable (i.e. no unresolved external references)
F_LNNO             = 0x0000004  # line numbers stripped from file
F_LSYMS            = 0x0000010  # local symbols stripped from file
F_MINMAL           = 0x0000020  # this is a minimal object file (".m") output of fextract
F_UPDATE           = 0x0000040  # this is a fully bound update file, output of ogen
F_SWABD            = 0x0000100  # this file as had its bytes swabbed (in names)
F_AR16WR           = 0x0000200  # this file has the byte ordering of an AR16WR machine (e.g. 11/70)
F_AR32WR           = 0x0000400  # this file has the byte ordering of an AR32WR machine (e.g. vax)
F_AR32W            = 0x0001000  # this file has the byte ordering of an AR32W  machine (e.g. 3b,maxi,MC68000)
F_PATCH            = 0x0002000  # file contains "patch" list in optional header
F_NODF             = 0x0002000  # (minimal file only) no decision functions for replaced functions
F_64INT            = 0x0004000  # basic int size is 64 bits

F_MIPS_NO_SHARED   = 0x0010000  # 
F_MIPS_SHARABLE    = 0x0020000  # 
F_MIPS_CALL_SHARED = 0x0030000  # 
F_MIPS_NO_REORG    = 0x0040000  # 
F_MIPS_UGEN_ALLOC  = 0x0100000  # 

ECOFF_FLAGS_NAMES = {
    F_RELFLG           : "RELFLG", 
    F_EXEC             : "EXEC", 
    F_LNNO             : "LNNO", 
    F_LSYMS            : "LSYMS", 
    F_MINMAL           : "MINMAL", 
    F_UPDATE           : "UPDATE", 
    F_SWABD            : "SWABD", 
    F_AR16WR           : "AR16WR", 
    F_AR32WR           : "AR32WR", 
    F_AR32W            : "AR32W", 
    F_PATCH            : "PATCH", 
    F_NODF             : "NODF", 
    F_64INT            : "64INT", 

    F_MIPS_NO_SHARED   : "MIPS_NO_SHARED",
    F_MIPS_SHARABLE    : "MIPS_SHARABLE",
    F_MIPS_CALL_SHARED : "MIPS_CALL_SHARED",
    F_MIPS_NO_REORG    : "MIPS_NO_REORG",
    F_MIPS_UGEN_ALLOC  : "MIPS_UGEN_ALLOC",
}

class ECOFFHeader:
    """
    struct filehdr {
        coff_ushort f_magic;    /* magic number */
        coff_ushort f_nscns;    /* number of sections */
        coff_int    f_timedat;  /* time & date stamp */
        coff_off    f_symptr;   /* file pointer to symbolic header */
        coff_int    f_nsyms;    /* sizeof(symbolic hdr) */
        coff_ushort f_opthdr;   /* sizeof(optional hdr) */
        coff_ushort f_flags;    /* flags */
    };
    """
    SIZE = 0x14

    def __init__(self, data):
        self.data = data[:ECOFFHeader.SIZE]
    
        self.f_magic, self.f_nscns, self.f_timedat, \
            self.f_symptr, self.f_nsyms, self.f_opthdr, \
                self.f_flags = struct.unpack(">HHIIIHH", self.data)

        assert self.f_magic in ECOFF_MAGIC_NAMES , "Magic value not recognized"

    def flags_to_str(self):
        return " ".join([ECOFF_FLAGS_NAMES[self.f_flags & (1 << i)] for i in range(32) if (self.f_flags & (1 << i)) != 0])

    def __str__(self):
        out = "ECOFF Header:\n"
        out += f"Magic: {ECOFF_MAGIC_NAMES[self.f_magic]} (0x{self.f_magic:04X})\n"
        out += f"Number of sections: {self.f_nscns}\n"
        out += f"Time: {self.f_timedat}\n"
        out += f"Symbolic Header Offset: 0x{self.f_symptr:X}\n"
        out += f"sizeof(Symbolic Header): 0x{self.f_nsyms:X}\n"
        out += f"sizeof(a.out Header): 0x{self.f_opthdr:X}\n"
        out += f"Flags: {self.flags_to_str()} (0x{self.f_flags:X})\n"

        return out

class ECOFFAOutHeader:
    """
    typedef struct aouthdr {
        coff_ushort magic;      /* same as for file header               */
        coff_ushort vstamp;     /* version stamp                         */
        // coff_ushort bldrev;  /*  */
        // coff_ushort padcell; /*  */
        coff_long   tsize;      /* text size in bytes, padded to DW bdry */
        coff_long   dsize;      /* initialized data                      */
        coff_long   bsize;      /* uninitialized data                    */
        coff_addr   entry;      /* entry pt.                             */
        coff_addr   text_start; /* base of text used for this file       */
        coff_addr   data_start; /* base of data used for this file       */
        coff_addr   bss_start;  /* base of bss used for this file        */
        coff_uint   gprmask;    /* general purpose register mask         */
        coff_word   cprmask[4]; /* co-processor register masks           */
        coff_long   gp_value;   /* the gp value used for this object     */
    } AOUTHDR;
    """
    SIZE = 0x38

    def __init__(self, data):
        self.data = data[:ECOFFAOutHeader.SIZE]
        
        self.magic, self.vstamp, \
            self.tsize, self.dsize, self.bsize, \
                self.entry, \
                    self.text_start, self.data_start, self.bss_start, \
                        self.gprmask, \
                            cprmask0, cprmask1, cprmask2, cprmask3, \
                                self.gp_value = struct.unpack(">HHIIIIIIIIIIIII", self.data)

        self.cprmask = (cprmask0, cprmask1, cprmask2, cprmask3)

    def __str__(self):
        out = "a.out header:\n"

        out += f"magic: 0x{self.magic:04X}\n"
        out += f"vstamp: {self.vstamp}\n"
        out += f"tsize: 0x{self.tsize:X}\n"
        out += f"dsize: 0x{self.dsize:X}\n"
        out += f"bsize: 0x{self.bsize:X}\n"
        out += f"entry: 0x{self.entry:08X}\n"
        out += f"text: 0x{self.text_start:X}\n"
        out += f"data: 0x{self.data_start:X}\n"
        out += f"bss: 0x{self.bss_start:X}\n"
        out += f"gprmask: 0b{self.gprmask:032b}\n"
        out += f"cprmask[0]: 0b{self.cprmask[0]:032b}\n"
        out += f"cprmask[1]: 0b{self.cprmask[1]:032b}\n"
        out += f"cprmask[2]: 0b{self.cprmask[2]:032b}\n"
        out += f"cprmask[3]: 0b{self.cprmask[3]:032b}\n"
        out += f"gp value: 0x{self.gp_value:08X}\n"

        return out

STYP_REG       = 0x00000000   #  "regular" section: allocated, relocated, loaded
STYP_DSECT     = 0x00000001   #  "dummy" section: not allocated, relocated, not loaded
STYP_NOLOAD    = 0x00000002   #  "noload" section: allocated, relocated,  not loaded
STYP_GROUP     = 0x00000004   #  "grouped" section: formed of input sections
STYP_PAD       = 0x00000008   #  "padding" section: not allocated, not relocated,  loaded
STYP_COPY      = 0x00000010   #  "copy" section: for decision function used by field update;  not allocated, not relocated, loaded;  reloc & lineno entries processed normally
STYP_TEXT      = 0x00000020   #  section contains text only
STYP_DATA      = 0x00000040   #  section contains data only
STYP_BSS       = 0x00000080   #  section contains bss only
STYP_RDATA     = 0x00000100   #  section contains read only data
STYP_SDATA     = 0x00000200   #  section contains small data only
STYP_SBSS      = 0x00000400   #  section contains small bss only
STYP_UCODE     = 0x00000800   #  section only contains ucodes
STYP_GOT       = 0x00001000   #
STYP_DYNAMIC   = 0x00002000   #
STYP_DYNSYM    = 0x00004000   #
STYP_REL_DYN   = 0x00008000   #
STYP_DYNSTR    = 0x00010000   #
STYP_HASH      = 0x00020000   #
STYP_DSOLIST   = 0x00040000   #
STYP_RESERVED1 = 0x00080000   #
STYP_CONFLICT  = 0x20100000   #
STYP_REGINFO   = 0x20200000   #
STYP_FINI      = 0x01000000   #  insts for .fini
STYP_EXTENDESC = 0x02000000   #  Escape bit for adding additional section type flags. The mask for valid values is 0x02FFF000. No other bits should be used.
STYP_RESERVED2 = 0x04000000   #  Reserved
STYP_LIT8      = 0x08000000   #  literal pool for 8 byte literals
STYP_LIT4      = 0x10000000   #  literal pool for 4 byte literals
S_NRELOC_OVFL  = 0x20000000   #  s_nreloc overflowed, the value is in v_addr of the first entry
STYP_LIB       = 0x40000000   #  section is a .lib section
STYP_INIT      = 0x80000000   #  section only contains the text instructions for the .init sec.
STYP_COMMENT   = 0x02100000   #
STYP_XDATA     = 0x02400000   #
STYP_PDATA     = 0x02800000   #

SECTYPE_NAMES = {
    STYP_REG       : "REG",
    STYP_DSECT     : "DSECT",
    STYP_NOLOAD    : "NOLOAD",
    STYP_GROUP     : "GROUP",
    STYP_PAD       : "PAD",
    STYP_COPY      : "COPY",
    STYP_TEXT      : "TEXT",
    STYP_DATA      : "DATA",
    STYP_BSS       : "BSS",
    STYP_RDATA     : "RDATA",
    STYP_SDATA     : "SDATA",
    STYP_SBSS      : "SBSS",
    STYP_UCODE     : "UCODE",
    STYP_GOT       : "GOT",
    STYP_DYNAMIC   : "DYNAMIC",
    STYP_DYNSYM    : "DYNSYM",
    STYP_REL_DYN   : "REL_DYN",
    STYP_DYNSTR    : "DYNSTR",
    STYP_HASH      : "HASH",
    STYP_DSOLIST   : "DSOLIST",
    STYP_RESERVED1 : "RESERVED1",
    STYP_CONFLICT  : "CONFLICT",
    STYP_REGINFO   : "REGINFO",
    STYP_FINI      : "FINI",
    STYP_EXTENDESC : "EXTENDESC",
    STYP_RESERVED2 : "RESERVED2",
    STYP_LIT8      : "LIT8",
    STYP_LIT4      : "LIT4",
    S_NRELOC_OVFL  : "NRELOC_OVFL",
    STYP_LIB       : "LIB",
    STYP_INIT      : "INIT",
    STYP_COMMENT   : "COMMENT",
    STYP_XDATA     : "XDATA",
    STYP_PDATA     : "PDATA",
}

class ECOFFSectionHeader:
    """
    struct scnhdr {
        char        s_name[8];  // section name
        coff_addr   s_paddr;    // physical address
        coff_addr   s_vaddr;    // virtual address
        coff_long   s_size;     // section size
        coff_off    s_scnptr;   // file ptr to raw data for section
        coff_off    s_relptr;   // file ptr to relocation
        coff_ulong  s_lnnoptr;  // file ptr to gp histogram
        coff_ushort s_nreloc;   // number of relocation entries
        coff_ushort s_nlnno;    // number of gp histogram entries
        coff_uint   s_flags;    // flags
    };
    """
    SIZE = 0x28

    def __init__(self, data):
        self.data = data[:ECOFFSectionHeader.SIZE]

        self.s_name = self.data[:8].decode("ASCII").replace("\0", "")
        
        self.s_paddr, self.s_vaddr, self.s_size, \
            self.s_scnptr, self.s_relptr, self.s_lnnoptr, \
            self.s_nreloc, self.s_nlnno, self.s_flags = struct.unpack(">IIIIIIHHI", self.data[8:])

        self.section_data = None

    def __str__(self):
        out = ""

        out += f""
        out += f"name    : {self.s_name}\n"
        out += f"paddr   : 0x{self.s_paddr:08X}\n"
        out += f"vaddr   : 0x{self.s_vaddr:08X}\n"
        out += f"size    : 0x{self.s_size:X}\n"
        out += f"scnptr  : 0x{self.s_scnptr:X}\n"
        out += f"relptr  : 0x{self.s_relptr:X}\n"
        out += f"lnnoptr : 0x{self.s_lnnoptr:X}\n"
        out += f"nreloc  : {self.s_nreloc}\n"
        out += f"nlnno   : {self.s_nlnno}\n"
        # TODO the field name suggests this should be treated as a set of bitflags but some section types are defined through multiple bits?
        out += f"flags   : {SECTYPE_NAMES[self.s_flags]} (0x{self.s_flags:08X})\n"
        return out

class ECOFFFile:

    def __init__(self, data):
        self.parent = self
        self.data = data
        self.header = ECOFFHeader(data)
        self.hdrr = EcoffHDRR(data[self.header.f_symptr:])
        self.aouthdr = ECOFFAOutHeader(data[ECOFFHeader.SIZE:])

        self.sections = []

        pos = ECOFFHeader.SIZE + ECOFFAOutHeader.SIZE
        for i in range(self.header.f_nscns):
            print(hex(pos))
            section = ECOFFSectionHeader(data[pos:])
            self.sections.append(section)
            section.section_data = self.data[section.s_scnptr:][:section.s_size]
            pos += ECOFFSectionHeader.SIZE


        self.fdrs = []
        for i in range(self.hdrr.ifdMax):
            fdr = EcoffFdr.from_binary(self, i)
            self.fdrs.append(fdr)

        for fdr in self.fdrs:
            fdr.late_init()

    def fdr_forname(self, filename):
        for fdr in self.fdrs:
            # remove path and file ext
            normalized_name = ".".join(fdr.name.split("/")[-1].split(".")[:-1])

            if normalized_name == filename:
                return fdr
        return None

    def fdr_foraddr(self, addr, extensions=('.c')):
        for fdr in self.fdrs:
            if fdr.adr == addr and any((fdr.name.endswith(ext) for ext in extensions)):
                return fdr
        return None

    def read_string(self, index):
        to = self.data.find(b'\0', self.hdrr.cbSsOffset + index)
        assert to != -1
        return self.data[self.hdrr.cbSsOffset + index:to].decode("ASCII")

    def read_ext_string(self, index):
        to = self.data.find(b'\0', self.hdrr.cbSsExtOffset + index)
        assert to != -1
        return self.data[self.hdrr.cbSsExtOffset + index:to].decode("ASCII")



if __name__ == '__main__':
    import sys
    from mips_isa import decode_insn, MIPS_BRANCH_INSNS, MIPS_BRANCH_LIKELY_INSNS, MIPS_INS_J, MIPS_INS_JAL

    coff = None
    with open(sys.argv[1], "rb") as file:
        coff = ECOFFFile(bytearray(file.read()))

    print(coff.header)
    print(coff.hdrr)
    for fdr in coff.fdrs:
        print(fdr.c_str())

    print(coff.aouthdr)
    for section in coff.sections:
        print(section)
        if section.s_flags == STYP_TEXT:
            cur_fdr = None
            cur_pdr = None

            def func_name(addr):
                if cur_fdr is None:
                    return None
                pdr = cur_fdr.pdr_foraddr(addr - cur_fdr.adr)
                return pdr.name if pdr is not None else None

            def lbl_name(addr):
                if cur_pdr is None:
                    return None
                lbl = cur_pdr.lookup_sym(addr, EcoffSt.LABEL)
                return lbl.name if lbl is not None else None

            insns = [i[0] for i in struct.iter_unpack(">I", section.section_data)]
            for i,insn in enumerate(insns):
                addr = section.s_vaddr + i * 4
                insn = decode_insn(insn,addr)

                fdr = coff.fdr_foraddr(addr, extensions=('.c', '.s'))
                if fdr is not None:
                    # debug_log(fdr.name)
                    cur_fdr = fdr

                # Get new pdr if there is one
                if cur_fdr is not None:
                    pdr = cur_fdr.pdr_foraddr(addr - cur_fdr.adr)
                    if pdr is not None:
                        # debug_log(pdr)
                        cur_pdr = pdr
                        print(f"\n{cur_pdr.name}")

                if cur_pdr is not None:
                    # Labels
                    lbl = lbl_name(addr)
                    if lbl is not None:
                        print(f"{lbl}:")

                    # Line numbers
                    asm_line = (addr - cur_pdr.addr - cur_fdr.adr) // 4
                    if asm_line < len(cur_pdr.lines):
                        src_inf = f" {cur_pdr.lines[asm_line]:4}"
                    else:
                        src_inf = " PADDING"
                else:
                    src_inf = ""

                mnemonic = insn.mnemonic
                op_str = insn.op_str
                if insn.id in MIPS_BRANCH_INSNS:
                    if insn.id in MIPS_BRANCH_LIKELY_INSNS:
                        lbl = lbl_name(insn.offset - 4)
                        if lbl is not None:
                            lbl += " + 4"
                    else:
                        lbl = lbl_name(insn.offset)

                    op_str_parts = []
                    for field in insn.fields:
                        if field == 'offset':
                            op_str_parts.append(lbl or insn.format_field(field))
                        else:
                            op_str_parts.append(insn.format_field(field))
                    op_str = ", ".join(op_str_parts)
                elif insn.id == MIPS_INS_J:
                    op_str = lbl_name(insn.target) or insn.op_str
                elif insn.id == MIPS_INS_JAL and cur_fdr is not None:
                    op_str = func_name(insn.target) or insn.op_str

                print(f"/* {addr:08X} {insn.raw:08X}{src_inf} */ {insn.mnemonic:12} {op_str}")
