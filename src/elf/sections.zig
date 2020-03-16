// Special sections defined in ELF standard

pub const SpecialSections = enum {
    /// uninitialized data
    .bss,
    /// version control information
    .comment,
    /// initialized data
    .data,
    /// initialized data
    .data1,
    /// information for symbolic debugging
    .debug,
    /// dynamic linking information
    .dynamic,
    /// symbol hash table
    .hash,
    /// line number information for symbolic debugging
    .line,
    ///
    .note,
    /// read-only data
    .rodata,
    /// read-only data
    .rodata1,
    /// holds section names
    .shstrtab,
    /// holds strings
    .strtab,
    /// holds a symbol table
    .symtab,
    /// holds executable instructions of a program
    .text,
};
