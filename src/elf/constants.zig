const std = @import("std");

pub const ElfClass = enum (u8) {
    Elf32 = 1,
    Elf64 = 2,
    _,

    pub fn AddressType(self: ElfClass) type {
        return switch (self) {
            .Elf32 => u32,
            .Elf64 => u64,
            else => unreachable,
        };
    }

    pub fn alignment(self: ElfClass) type {
        return switch (self) {
            .Elf32 => 4,
            .Elf64 => 8,
            else => unreachable,
        };
    }
};

pub const ElfEndian = enum (u8) {
    Little = 1,
    Big = 2,
    _,
};

pub const ElfAbi = enum (u8) {
    SystemV = 0x00,
    HP_UX = 0x01,
    NetBsd = 0x02,
    Linux = 0x03,
    GnuHurd = 0x04,
    Solaris = 0x06,
    Aix = 0x07,
    Irix = 0x08,
    FreeBsd = 0x09,
    Tru64 = 0x0A,
    NovellModesto = 0x0B,
    OpenBSD = 0x0C,
    OpenVms = 0x0D,
    NonStopKernel = 0x0E,
    Aros = 0x0F,
    FenixOs = 0x10,
    CloudAbi = 0x11,
    StratusTechnologiesOpenVOs = 0x12,
    _,
};

pub const ElfObjType = enum (u16) {
    pub const lo_os = 0xfe00;
    pub const hi_os = 0xfeff;
    pub const lo_proc = 0xff00;
    pub const hi_proc = 0xffff;

    None = 0x00,
    Rel = 0x01,
    Exec = 0x02,
    Dyn = 0x03,
    Core = 0x04,
    _,
};

pub const ElfMachine = enum (u16) {
    None = 0x00,
    Sparc = 0x02,
    X86 = 0x03,
    Mips = 0x08,
    PowerPc = 0x14,
    S390 = 0x16,
    Arm = 0x28,
    SuperH = 0x2A,
    Ia64 = 0x32,
    Amd64 = 0x3E,
    AArch64 = 0xB7,
    RiscV = 0xF3,
    _,
};

pub const ElfPhType = enum (u32) {
    const lo_proc = 0x7000_0000;
    const hi_proc = 0x7FFF_FFFF;

    /// Program header table entry unused
    Null = 0x0,
    /// Loadable segment
    Load = 0x1 ,
    /// Dynamic linking information
    Dynamic = 0x2,
    /// Interpreter information
    Interp = 0x3,
    /// Auxiliary information
    Note = 0x4,
    /// reserved
    Shlib = 0x5,
    /// segment containing program header table itself
    Phdr = 0x6,
    /// Thread-Local Storage template
    Tls = 0x7,
    _,
};

/// Program header flags
pub const PF = struct {
    pub const MASKPROC = 0xf000_0000;

    pub const X = 0x01;
    pub const W = 0x02;
    pub const R = 0x04;
};

pub const ElfShType = enum (u32) {
    ///  Start OS-specific.
    const lo_proc = 0x7000_0000;
    const hi_proc = 0x7FFF_FFFF;
    const lo_user = 0x8000_0000;
    const hi_user = 0xfFFF_FFFF;

    /// Section header table entry unused
    Null = 0x0,
    /// Program data
    ProgBits = 0x1,
    /// Symbol table
    SymTab = 0x2,
    /// String table
    StrTab = 0x3,
    /// Relocation entries with addends
    Rela = 0x4,
    /// Symbol hash table
    Hash = 0x5,
    /// Dynamic linking information
    Dynamic = 0x6,
    /// Notes
    Note = 0x7,
    /// Program space with no data (bss)
    NoBits = 0x8,
    /// Relocation entries, no addends
    Rel = 0x9,
    ///  Reserved
    Shlib = 0x0A,
    ///  Dynamic linker symbol table
    DynSym = 0x0B,
    ///  Array of constructors
    InitArray = 0x0E,
    ///  Array of destructors
    FiniArray = 0x0F,
    ///  Array of pre-constructors
    PreinitArray = 0x10,
    ///  Section group
    Group = 0x11,
    ///  Extended section indices
    SymTabSectionIndices = 0x12,
    ///  Number of defined types.
    Num = 0x13,
    _,
};

pub const SHF = struct {
    ///  OS-specific
    pub const MaskOs   = 0x0ff0_0000;
    ///  Processor-specific
    pub const MaskProc = 0xf000_0000;

    ///  Writable
    pub const WRITE = 0x1;
    ///  Occupies memory during execution
    pub const ALLOC = 0x2;
    ///  Executable
    pub const EXECINSTR = 0x4;
    ///  Might be merged
    pub const MERGE = 0x10;
    ///  Contains nul-terminated strings
    pub const STRINGS = 0x20;
    ///  'sh_info' contains SHT index
    pub const INFOLINK = 0x40;
    ///  Preserve order after combining
    pub const LINKORDEr = 0x80;
    ///  Non-standard OS specific handling required
    pub const OSNONCONFORMING = 0x100;
    ///  Section is member of a group
    pub const GROUP = 0x200;
    ///  Section hold thread-local data
    pub const TLS = 0x400;
    ///  Special ordering requirement (Solaris)
    pub const ORDERED = 0x4000_0000;
    ///  Section is excluded unless referenced or allocated (Solaris)
    pub const EXCLUDE = 0x8000_0000;
};

/// Special Section Indices
///
/// Some section header table indexes are reserved; an object file will not
/// have sections for these special indexes.
pub const SHN = enum(u16) {
    pub const lo_reserve = 0xff00;
    pub const hi_reserve = 0xffff;
    pub const lo_proc = 0xff00;
    pub const hi_proc = 0xff1f;

    /// Marks an undefined, missing, irrelevant or otherwise meaningless section reference
    Undef = 0x0000,

    /// This value specifies absolute values for the corresponding reference
    Abs = 0xfff1,

    /// Symbols defined relative to this section are common symbols
    /// eg: Fortran `COMMON` or unallocated C external variables
    Common = 0xfff2,

    _,
};
