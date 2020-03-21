const std = @import("std.zig");
const constants = @import("constants.zig");

const ElfClass = constants.ElfClass;

const SymIndex = u32;

/// Relocation types for X86_64
///
/// A: Represents the addend used to compute the value of the relocatable field.
/// B: Represents the base address where object file is loaded in memory.
/// G: Represents the offset into the global offset table at which the relocation entry’s symbol will reside during execution.
/// GOT: Represents the address of the global offset table.
/// L: Represents the place of the Procedure Linkage Table entry for a symbol.
/// P: Represents the place of the storage unit being relocated.
/// S: Represents the value of the symbol whose index resides in the relocation entry.
/// Z: Represents the size of the symbol whose index resides in the relocation entry.
pub const R_X86_64 = enum(u8) {
    /// R_X86_64_NONE (none),  none
    R_X86_64_NONE = 0,
    /// R_X86_64_64 (word64), S + A
    R_X86_64_64 = 1,
    /// R_X86_64_PC32 (word32), S + A - P
    R_X86_64_PC32 = 2,
    /// R_X86_64_GOT32 (word32), G + A
    R_X86_64_GOT32 = 3,
    /// R_X86_64_PLT32 (word32), L + A - P
    R_X86_64_PLT32 = 4,
    /// R_X86_64_COPY (none), none
    R_X86_64_COPY = 5,
    /// R_X86_64_GLOB_DAT (word64), S
    R_X86_64_GLOB_DAT = 6,
    /// R_X86_64_JUMP_SLOT (word64), S
    R_X86_64_JUMP_SLOT = 7,
    /// R_X86_64_RELATIVE (word64), B + A
    R_X86_64_RELATIVE = 8,
    /// R_X86_64_GOTPCREL (word32), G + GOT + A -P
    R_X86_64_GOTPCREL = 9,
    /// R_X86_64_32 (word32), S + A
    R_X86_64_32 = 10,
    /// R_X86_64_32S (word32), S + A
    R_X86_64_32S = 11,
    /// R_X86_64_16 (word16), S + A
    R_X86_64_16 = 12,
    /// R_X86_64_PC16 (word16), S + A - P
    R_X86_64_PC16 = 13,
    /// R_X86_64_8 (word8), S + A
    R_X86_64_8 = 14,
    /// R_X86_64_PC8 (word8), S + A - P
    R_X86_64_PC8 = 15,
    /// R_X86_64_DTPMOD64 (word64),
    R_X86_64_DTPMOD64 = 16,
    /// R_X86_64_DTPOFF64 (word64),
    R_X86_64_DTPOFF64 = 17,
    /// R_X86_64_TPOFF64 (word64),
    R_X86_64_TPOFF64 = 18,
    /// R_X86_64_TLSGD (word32),
    R_X86_64_TLSGD = 19,
    /// R_X86_64_TLSLD (word32),
    R_X86_64_TLSLD = 20,
    /// R_X86_64_DTPOFF32 (word32),
    R_X86_64_DTPOFF32 = 21,
    /// R_X86_64_GOTTPOFF (word32),
    R_X86_64_GOTTPOFF = 22,
    /// R_X86_64_TPOFF32 (word32),
    R_X86_64_TPOFF32 = 23,
    /// R_X86_64_PC64 (word64), S + A - P
    R_X86_64_PC64 = 24,
    /// R_X86_64_GOTOFF64 (word64), S + A - GOT
    R_X86_64_GOTOFF64 = 25,
    /// R_X86_64_GOTPC32 (word32), GOT + A - P
    R_X86_64_GOTPC32 = 26,
    /// R_X86_64_SIZE32 (word32), Z + A
    R_X86_64_SIZE32 = 32,
    /// R_X86_64_SIZE64 (word64), Z + A
    R_X86_64_SIZE64 = 33,
    /// R_X86_64_GOTPC32_TLSDESC (word32),
    R_X86_64_GOTPC32_TLSDESC = 34,
    /// R_X86_64_TLSDESC_CALL (none),
    R_X86_64_TLSDESC_CALL = 35,
    /// R_X86_64_TLSDESC (word64×2),
    R_X86_64_TLSDESC = 36,
    /// R_X86_64_IRELATIVE (word64), indirect (B + A)
    R_X86_64_IRELATIVE = 37,

    pub fn info(comptime elf_class: ElfClass, sym: SymIndex, type_: @This()) elf_class.AddressType() {
        return relInfo(elf_class, sym, @enumToInt(type_));
    }
};

pub fn relInfo(comptime elf_class: ElfClass, sym: SymIndex, type_: u8) elf_class.AddressType() {
    const AddressType = elf_class.AddressType();
    const sym_offset = switch (elf_class) {
        .Elf32 => 8,
        .Elf64 => 32,
        else => unreachable,
    };

    if (elf_class == .Elf32) {
        assert(sym <= std.math.maxInt(u24));
    }

    return (
        (@intCast(AddressType, type_) << 0)
        | (@intCast(AddressType, sym) << sym_offset)
    );
}
