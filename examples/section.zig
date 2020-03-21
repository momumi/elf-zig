const std = @import("std");
const builtin = @import("builtin");

const warn = std.debug.warn;
const assert = std.debug.assert;

const elf = @import("elf");

const ElfFile = elf.ElfFile;
const Segment = elf.Segment;
const Section = elf.Section;
const Symbol = elf.Symbol;
const SectionData = elf.SectionData;

const PF = elf.constants.PF;
const SHF = elf.constants.SHF;

const R_X86_64 = elf.relocation.R_X86_64;

/// little-endian byte n
fn leByte(x: var, n: u8) u8 {
    return @intCast(u8, (@intCast(u64, x) >> @intCast(u6, 8*n)) & 0xff);
}

pub fn main() anyerror!void {
    const out_file_name = "test_elf";

    // msg length
    const msg_len = 0xc;
    const page_alignment = 0x1000; // 4KiB pages

    // NOTE: And executables use virtual addresses based on where the code/data
    // will be placed into RAM.
    //
    // Object files usually treat each section as starting at address
    // zero and symbols are refrenced accordingly.
    //
    // However, for this example we account for this and adjust the relocation
    // values such that the ELF file we generate can be used both as an executable
    // and object file.
    //
    // eg: run it as an executable:
    // ./test_elf
    //
    // eg: link it as an object file:
    // ld ./test_elf
    // ./a.out
    //
    // eg: examine generated elf files:
    // readelf -Wa test_elf
    // readelf -Wa a.out
    //
    //
    const base_addr = 0x0001_00b0;

    // uncomment this line, and we will create a normal relocatable object
    // with base_addr zero.
    // const base_addr = 0x0000_0000;

    const msg_addr = base_addr + 0x0000_0000;
    const entry_address = base_addr + msg_len;

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    var elf_file = try ElfFile(.Elf64).init(
        .Little,
        .Linux,
        0,
        if (base_addr == 0) .Rel else .Exec,
        .Amd64,
        entry_address,
        0,
        &arena.allocator
    );

    const len0 = leByte(msg_len, 0);
    const len1 = leByte(msg_len, 1);
    const len2 = leByte(msg_len, 2);
    const len3 = leByte(msg_len, 3);

    const msg0 = leByte(msg_addr, 0);
    const msg1 = leByte(msg_addr, 1);
    const msg2 = leByte(msg_addr, 2);
    const msg3 = leByte(msg_addr, 3);

    // location where msg_addr is used in `mov rsi, msg_addr` instruction
    const msg_addr_offset = 0x11 + 2;

    const program = [_]u8 {
        'h', 'e', 'l', 'l', 'o', ' ', 'w', 'o', 'r', 'l', 'd', '\n',
        0xba, len0, len1, len2, len3,              // 000c: mov    edx,0xc       ; edx = msg_len
        0x48, 0xbe, msg0, msg1, msg2, msg3, 0x00,  // 0011: mov    rsi,0x1_0080  ; rsi = &msg
        0x00, 0x00, 0x00,                          //     :
        0xbf, 0x01, 0x00, 0x00, 0x00,              //     : mov    edi,0x1       ; STDOUT=1
        0xb8, 0x01, 0x00, 0x00, 0x00,              //     : mov    eax,0x1       ; write()
        0x0f, 0x05,                                //     : syscall
        0x48, 0x31, 0xff,                          //     : xor    rdi,rdi       ; rdi = 0
        0xb8, 0x3c, 0x00, 0x00, 0x00,              //     : mov    eax,0x3c      ; exit(rdi)
        0x0f, 0x05,                                //     : syscall
    };

    const program_seg = Segment(.Elf64) {
        .ph_type = .Load,
        .vaddr = base_addr,
        .paddr = base_addr,
        .data = program[0..],
        .alignment = 0x1000,
        .memsz = program.len,
        .flags = PF.R + PF.X,
    };

    const program_seg_ndx: u32 = try elf_file.addSegment(program_seg);

    var shstrtab = try elf.StringTable.init(&arena.allocator);
    const shstrtab_index = try elf_file.addShStrTab(&shstrtab);

    // basic sections
    const text_sec = Section(.Elf64) {
        .name = try shstrtab.addString(".text"),
        .sh_type = .ProgBits,
        .flags = SHF.ALLOC + SHF.EXECINSTR,
        .addr = program_seg.vaddr,
        .link = program_seg_ndx,
        .info = 0, // ?
        .alignment = program_seg.alignment,
        .entsize = 0,

        .data = SectionData(.Elf64) { .SegmentIndex = program_seg_ndx },
    };

    const text_sh_ndx: u32 = try elf_file.addSection(text_sec);

    // .strtab table
    var strtab = try elf.StringTable.init(&arena.allocator);
    const strtab_name = try shstrtab.addString(".strtab");
    const strtab_index = try elf_file.addStringTable(strtab_name, &strtab);

    // .symtab table
    var symtab = try elf.SymbolTable(.Elf64).init(&arena.allocator);

    // add symbols to the table
    const text_symb = Symbol(.Elf64) {
        .name = try strtab.addString(".text"),
        .value = program_seg.vaddr,
        .size = program_seg.data.len,
        .type_ = .Section,
        .bind = .Local,
        .visbility = .Default,
        .shndx = @intCast(u16, text_sh_ndx),
    };
    const text_symb_index = try symtab.addSymbol(text_symb);

    const msg_symb = Symbol(.Elf64) {
        .name = try strtab.addString("msg"),
        .value = msg_addr,
        .size = msg_len,
        .type_ = .NoType,
        .bind = .Local,
        .visbility = .Default,
        .shndx = @intCast(u16, text_sh_ndx),
    };
    const msg_symb_index = try symtab.addSymbol(msg_symb);

    const start_symb = Symbol(.Elf64) {
        .name = try strtab.addString("_start"),
        .value = entry_address,
        .size = 0,
        .type_ = .NoType,
        .bind = .Global,
        .visbility = .Default,
        .shndx = @intCast(u16, text_sh_ndx),
    };
    const start_symb_index = try symtab.addSymbol(start_symb);

    const symtab_name = try shstrtab.addString(".symtab");
    const symtab_ndx = try elf_file.addSymbolTable(symtab_name, &symtab, strtab_index);

    // add a relocation table
    var rela = try elf.RelaTable(.Elf64).init(&arena.allocator);
    const rela_name = try shstrtab.addString(".rela.text");

    const rela0 = elf.headers.ElfRela(.Elf64) {
        // offset of the data to be relocated form the start of `.text` section
        .offset = msg_addr_offset,
        .info = R_X86_64.info(.Elf64, msg_symb_index, .R_X86_64_64),
        .addend = if (base_addr == 0)
            msg_addr
        else
            @bitCast(u64, @intCast(i64, -2*base_addr)),
    };
    const rela0_ndx = try rela.addRelocation(rela0);

    const rela_table_index = try elf_file.addRelaTable(rela_name, &rela, symtab_ndx, text_sh_ndx);

    // add a custom StrTab section
    {
        const name = try shstrtab.addString(".my_strings");
        var my_strings = try elf.StringTable.init(&arena.allocator);
        const ndx1 = try my_strings.addString(".text.blah");
        const ndx2 = try my_strings.addString(".text.hello");
        const ndx3 = try my_strings.addString("123@x^&ello");

        const my_strings_ndx: u32 = try elf_file.addStringTable(name, &my_strings);
    }

    // write the ELF file to disk
    {
        std.debug.warn("ELF file written to: {}\n", .{out_file_name});

        const cwd = std.fs.cwd();
        var file = try cwd.createFile(out_file_name, .{.mode = 0o744});
        defer file.close();

        const file_out_stream = file.outStream();
        var buf_stream = std.io.bufferedOutStream(file_out_stream);
        const out_stream = buf_stream.outStream();
        try elf_file.write(out_stream);
        try buf_stream.flush();

        std.debug.warn("Now try running the file with:\n./{}\n\n" , .{out_file_name});
        std.debug.warn("Or linking and running the ELF file\nld {}\n./a.out\n" , .{out_file_name});
    }
}
