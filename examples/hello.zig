const std = @import("std");
const builtin = @import("builtin");

const warn = std.debug.warn;
const assert = std.debug.assert;

const elf = @import("elf");

const ElfFile = elf.ElfFile;
const Segment = elf.Segment;
const Section = elf.Section;

const PF = elf.constants.PF;

/// little-endian byte n
fn leByte(x: var, n: u8) u8 {
    return @intCast(u8, (@intCast(u64, x) >> @intCast(u6, 8*n)) & 0xff);
}

pub fn main() anyerror!void {
    const out_file_name = "hello_elf";

    // msg length
    const msg_len = 0xc;
    const page_alignment = 0x1000; // 4KiB pages
    const base_addr = 0x0001_0078;
    const entry_address = base_addr + msg_len;

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    var elf_file = try ElfFile(.Elf64).init(
        .Little,
        .Linux,
        0,
        .Exec,
        .Amd64,
        entry_address,
        0,
        &arena.allocator
    );

    const len0 = leByte(msg_len, 0);
    const len1 = leByte(msg_len, 1);
    const len2 = leByte(msg_len, 2);
    const len3 = leByte(msg_len, 3);

    const msg0 = leByte(base_addr, 0);
    const msg1 = leByte(base_addr, 1);
    const msg2 = leByte(base_addr, 2);
    const msg3 = leByte(base_addr, 3);

    const program = [_]u8 {
        'h', 'e', 'l', 'l', 'o', ' ', 'w', 'o', 'r', 'l', 'd', '\n',
        0xba, len0, len1, len2, len3,              //   : mov    edx,0xc       ; edx = msg_len
        0x48, 0xbe, msg0, msg1, msg2, msg3, 0x00,  //   : movabs rsi,0x1_0080  ; rsi = &msg
        0x00, 0x00, 0x00,                          //   :
        0xbf, 0x01, 0x00, 0x00, 0x00,              //   : mov    edi,0x1       ; STDOUT=1
        0xb8, 0x01, 0x00, 0x00, 0x00,              //   : mov    eax,0x1       ; write()
        0x0f, 0x05,                                //   : syscall
        0x48, 0x31, 0xff,                          //   : xor    rdi,rdi       ; rdi = 0
        0xb8, 0x3c, 0x00, 0x00, 0x00,              //   : mov    eax,0x3c      ; exit(rdi)
        0x0f, 0x05,                                //   : syscall
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

    const program_seg_index = try elf_file.addSegment(program_seg);

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

        std.debug.warn("Now try running the file with:\n./{}\n" , .{out_file_name});
    }
}
