OUTPUT_ARCH(mips)
ENTRY(_start)

SECTIONS {
    . = start;

    .text :
    {
        PROVIDE(_start = .);
        *(.text*)
    }

    /DISCARD/ :
    {
        *(*);
    }
}
