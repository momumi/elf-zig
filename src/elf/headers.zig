const std = @import("std");

usingnamespace(@import("constants.zig"));

pub const ElfHeader32 = ElfHeader(.Elf32);
pub const ElfHeader64 = ElfHeader(.Elf64);

pub fn ElfHeader(elf_class: ElfClass) type {
    return struct {
        pub const AddressType = elf_class.AddressType();
        pub const header_size = switch (elf_class) {
            .Elf32 => 0x34, // 52 bytes
            .Elf64 => 0x40, // 64 bytes
            else => unreachable,
        };

        magic: [4]u8 = [4]u8 { 0x7F, 'E', 'L', 'F' },
        class: ElfClass = elf_class,
        endian: ElfEndian,
        version: u8 = 1,
        abi: ElfAbi,
        abi_version: u8,
        _reserved0: [7]u8 = [1]u8 {0} ** 7,
        obj_type: ElfObjType,
        machine: ElfMachine,
        elf_version: u32 = 1,
        /// offset to program entry point
        entry: AddressType,
        /// program header offset
        phoff: AddressType,
        /// section header offset
        shoff: AddressType,
        /// ISA specific flags
        flags: u32,
        /// Size of the elf header
        ehsize: u16 = header_size,
        /// size of entry in the program header table
        phentsize: u16 = ElfProgramHeader(elf_class).header_size,
        /// number of entries in the program header table
        phnum: u16,
        /// size of entry in the section header table
        shentsize: u16 = ElfSectionHeader(elf_class).header_size,
        /// number of entries in the section header table
        shnum: u16,
        /// index into section header that contains section name strings (.shstrtab section)
        shstrndx: u16,
    };
}

pub fn ElfProgramHeader(elf_class: ElfClass) type {
    const Header32 = struct {
        pub const AddressType = elf_class.AddressType();
        pub const header_size = 0x20; // 32 bytes

        ph_type: ElfPhType,
        offset: AddressType,
        vaddr: AddressType,
        paddr: AddressType,
        filesz: AddressType,
        memsz: AddressType,
        align_: AddressType,
        /// segment dependent flags
        flags: u32,
    };

    const Header64 = struct {
        pub const AddressType = elf_class.AddressType();
        pub const header_size = 0x38; // 56 bytes

        ph_type: ElfPhType,
        /// segment dependent flags
        flags: u32,
        offset: AddressType,
        vaddr: AddressType,
        paddr: AddressType,
        filesz: AddressType,
        memsz: AddressType,
        align_: AddressType,
    };

    // Note: position of `flags` field is different between 32 and 64 bit
    return switch (elf_class) {
        .Elf32 => Header32,
        .Elf64 => Header64,
        else => unreachable,
    };
}

pub fn ElfSectionHeader(elf_class: ElfClass) type {
    return struct {
        pub const AddressType = elf_class.AddressType();
        pub const header_size = switch (elf_class) {
            .Elf32 => 0x28, // 40
            .Elf64 => 0x40, // 64
            else => unreachable,
        };

        pub const Flags = struct {
        };

        name: u32,
        sh_type: ElfShType,
        flags: AddressType,
        addr: AddressType,
        offset: AddressType,
        size: AddressType,
        link: u32,
        info: u32,
        addralign: AddressType,
        entsize: AddressType,
    };
}

test "ELF" {
    const elf32 = ElfHeader32 {
        .endian = .Little,
        .abi = .Linux,
        .abi_version = 0,
        .obj_type = .Exec,
        .machine = .X86,
        .entry = 0x200,
        .phoff = 0x34,
        .shoff = 0x400,
        .flags = 0,
        .phnum = 2,
        .shnum = 2,
        .shstrndx = 0,
    };

    const elf64 = ElfHeader64 {
        .endian = .Little,
        .abi = .Linux,
        .abi_version = 0,
        .obj_type = .Exec,
        .machine = .X86,
        .entry = 0x200,
        .phoff = 0x34,
        .shoff = 0x400,
        .flags = 0,
        .phnum = 2,
        .shnum = 2,
        .shstrndx = 0,
    };

    warn("elf32: {}\n", .{elf32});
    warn("\n", .{});
    warn("elf64: {}\n", .{elf64});

}
