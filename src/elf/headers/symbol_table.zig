const std = @import("std");
const constants = @import("../constants.zig");

const ElfClass = constants.ElfClass;

/// Symbol Table Type
pub const STT = enum(u4) {
    pub const lo_proc = 0xd;
    pub const hi_proc = 0xf;

    NoType = 0,
    Object = 1,
    Func = 2,
    Section = 3,
    File = 4,
    Common = 5,
    Tls = 6,
    Num = 7,
    _,
};

/// Symbol Table Bind
pub const STB = enum(u4) {
    pub const lo_proc = 0xd;
    pub const hi_proc = 0xf;

    Local = 0,
    Global = 1,
    Weak = 2,
    Num = 3,
    _,
};

/// Symbol Table Bind
pub const STV = enum(u4) {
    pub const lo_proc = 0xd;
    pub const hi_proc = 0xf;

    Default = 0,
    Internal = 1,
    Hidden = 2,
    Protected = 3,
    _,
};

pub fn stInfo(stt: STT, stb: STB) u8 {
    return (
        (@intCast(u8, @enumToInt(stt)) << 0)
        | (@intCast(u8, @enumToInt(stb)) << 4)
    );
}

/// Extracts STT from st_info
pub fn stType(type_: u8) STT {
    return (type_ >> 0) & 0xf;
}

/// Extracts STB from st_info
pub fn stBind(bind: u8) STB {
    return (bind >> 4) & 0xf;
}

pub fn ElfSymbolTableEntry(elf_class: ElfClass) type {
    const Entry32 = struct {
        pub const AddressType = elf_class.AddressType();
        pub const entry_size = 0x10; // 16 bytes

        name: u32,
        value: AddressType,
        size: AddressType,
        info: u8,
        other: u8,
        shndx: u16,
    };

    const Entry64 = struct {
        pub const AddressType = elf_class.AddressType();
        pub const entry_size = 0x18; // 24 bytes

        name: u32,
        info: u8,
        other: u8,
        shndx: u16,
        value: AddressType,
        size: AddressType,
    };

    // std.debug.assert(@sizeOf(Entry32) == Entry32.entry_size);
    // std.debug.assert(@sizeOf(Entry64) == Entry64.entry_size);

    return switch (elf_class) {
        .Elf32 => Entry32,
        .Elf64 => Entry64,
        else => unreachable,
    };
}
