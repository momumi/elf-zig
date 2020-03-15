const std = @import("std");

const assert = std.debug.assert;

usingnamespace(@import("constants.zig"));
pub const headers = @import("headers.zig");

const ArrayList = std.ArrayList;

// pub const constants = @import("constants.zig");
// pub const ElfClass = constants.ElfClass;

const ElfHeader = headers.ElfHeader;
const ElfProgramHeader = headers.ElfProgramHeader;
const ElfSectionHeader = headers.ElfSectionHeader;

pub fn Segment(elf_class: ElfClass) type {
    return struct {
        const AddressType = elf_class.AddressType();

        ph_type: ElfPhType,
        vaddr: AddressType,
        paddr: AddressType,
        data: []const u8,
        memsz: AddressType,
        alignment: AddressType,
        flags: u32,

        _calculated_offset: u64 = undefined,
    };
}

pub fn Section(elf_class: ElfClass) type {
    return struct {
        const AddressType = elf_class.AddressType();

        name: [:0]const u8,
        sh_type: ElfShType,
        flags: AddressType,
        addr: AddressType,
        link: u32,
        info: u32,
        size: AddressType,
        alignment: AddressType,
    };
}

pub fn ElfFile(elf_class: ElfClass) type {
    return struct {
        const AddressType = elf_class.AddressType();
        const SegmentType = Segment(elf_class);
        const SectionType = Section(elf_class);
        const elf_class: ElfClass = elf_class;

        /// All of the headers in the elf file should have this alignment
        const elf_header_alignment = switch (elf_class) {
            .Elf32 => 4,
            .Elf64 => 8,
            else => unreachable,
        };

        endian: ElfEndian,
        abi: ElfAbi,
        abi_version: u8,
        obj_type: ElfObjType,
        machine: ElfMachine,
        /// offset to program entry point
        entry: AddressType,
        /// ISA specific flags
        flags: u32,

        segments: ArrayList(SegmentType),
        sections: ArrayList(SectionType),


        pub fn init(
            endian: ElfEndian,
            abi: ElfAbi,
            abi_version: u8,
            obj_type: ElfObjType,
            machine: ElfMachine,
            entry: AddressType,
            flags: u32,
            alloc: *std.mem.Allocator
        ) @This() {
            return @This() {
                .endian = endian,
                .abi = abi,
                .abi_version = abi_version,
                .obj_type = obj_type,
                .machine = machine,
                .entry = entry,
                .flags = flags,
                .segments = ArrayList(SegmentType).init(alloc),
                .sections = ArrayList(SectionType).init(alloc),
            };
        }

        /// Offset into the ELF file where the ELF header itself will be stored
        ///
        /// The elf header is always at the start of the file
        fn elfHeaderOffset(self: @This()) u64 {
            return 0;
        }

        /// Offset into the ELF file where program headers will be stored
        ///
        /// Program headers are stored after the elf header
        fn phOffset(self: @This()) u64 {
            if (self.segments.len == 0) {
                return 0;
            }

            return (
                self.elfHeaderOffset()
                + ElfHeader(elf_class).header_size
            );
        }

        /// Offset into the ELF file where segments will be stored
        ///
        /// Segments are stored after the program headers
        fn segmentsOffset(self: @This()) u64 {
            if (self.segments.len == 0) {
                return 0;
            }

            // find the size of all the program headers and where they end
            const ph_num = self.segments.len;
            const ph_size = ElfProgramHeader(elf_class).header_size;
            const ph_total_size = ph_num * ph_size;
            const ph_list_end = self.phOffset() + ph_total_size;

            // find out the necessary alignment for the first segment
            const segment = self.segments.at(0);
            const padding = calcAddrPadding(ph_list_end, segment.vaddr, segment.alignment);

            return ph_list_end + padding;
        }

        /// Offset into the ELF file where section headers will be stored
        ///
        /// Section headers are stored after all the segments
        fn shOffset(self: @This()) u64 {
            if (self.numSections() == 0) {
                return 0;
            }

            var pos = self.segmentsOffset();

            for (self.segments.toSlice()) |segment| {
                const alignment = segment.alignment;
                const padding = calcAddrPadding(pos, segment.vaddr, alignment);
                pos += segment.data.len + padding;
            }

            // elf headers must match align with machine word size
            pos += calcPadding(pos, @This().elf_header_alignment);

            return pos;
        }

        /// Calculate the amount of padding needed to reach alignment
        fn calcPadding(offset: u64, alignment: u64) u64 {
            if (alignment <= 1 or offset % alignment == 0) {
                return 0;
            }
            assert(@popCount(u64, alignment) == 1);

            return alignment - (offset & (alignment-1));
        }

        /// Given an offset in the file and an address, compute the amount
        /// of padding needed to satisfy:
        ///     (offset + padding) % alignment == addr % alignment
        fn calcAddrPadding(offset: u64, addr: u64, alignment: u64) u64 {
            if (alignment <= 1) {
                return 0;
            }
            const offset_misalign = (offset % alignment);
            const addr_misalign = (addr % alignment);
            if (offset_misalign == addr_misalign) {
                return 0;
            } else if (offset_misalign < addr_misalign) {
                return addr_misalign - offset_misalign;
            } else if (offset_misalign > addr_misalign) {
                return (addr_misalign + alignment) - offset_misalign;
            } else {
                unreachable;
            }
        }

        fn addPadding(serializer: var, num_bytes: u64) !void {
            var i: usize = 0;
            const zero: u8 = 0;
            while (i < num_bytes) : (i += 1) {
                try serializer.serializeInt(zero);
            }
        }

        const PN_XNUM = 0xffff;

        const SHN_LORESERVE = 0xff00;
        const SHN_XINDEX = 0xffff;

        fn numSegments(self: @This()) AddressType {
            return self.segments.len;
        }

        /// Value of phnum in the ELF header
        fn phNum(self: @This()) u16 {
            if (self.numSegments() >= PN_XNUM) {
                return PN_XNUM;
            } else {
                return @intCast(u16, self.numSegments());
            }
        }

        fn hasShStrTab(self: @This()) bool {
            return self.sections.len > 0;
        }

        fn hasShIndex0(self: @This()) bool {
            return (
                (self.sections.len > 0)
                or (self.phNum() == PN_XNUM)
            );
        }

        fn numSections(self: @This()) AddressType {
            var num_sections = @intCast(AddressType, self.sections.len);
            num_sections += @bitCast(u1, self.hasShStrTab());
            num_sections += @bitCast(u1, self.hasShIndex0());
            return num_sections;
        }

        /// Value of shnum in the ELF header
        /// If ≥0xff00 sections, then set shnum=0, and store real value
        fn shNum(self: @This()) u16 {
            const num_sections = self.numSections();
            if (num_sections >= SHN_LORESERVE) {
                return 0;
            } else {
                return @intCast(u16, num_sections);
            }
        }

        /// Use the last entry in the table to store .shstrtab entry
        fn stringTableIndex(self: @This()) AddressType {
            const num_sections = self.numSections();
            if (num_sections == 0) {
                return 0;
            } else {
                return num_sections - 1;
            }
        }

        /// Value of shstrndx in the ELF header
        fn shStrNdx(self: @This()) u16 {
            const num_sections = self.numSections();
            if (num_sections == 0) {
                return 0;
            }

            const shstrndx = self.stringTableIndex();
            if (shstrndx >= SHN_LORESERVE) {
                return SHN_XINDEX;
            } else {
                return @intCast(u16, shstrndx);
            }
        }


        // pub fn write(self: @This(), out_stream: *std.io.Stream(StreamErrorType), StreamErrorType) type) !void {
        pub fn write(self: @This(), out_stream: var) !void {
            // Layout of how we will write the ELF file:
            //
            // ELF header
            // Phdr0 (self.segment[0])
            // ...
            // PhdrN (self.segment[N])
            // Segments0 (self.segment[0].data)
            // ...
            // SegmentsN (self.segment[N].data)
            // Shdr0 (Index0 Shdr SHT_NULL)
            // Shdr1 (self.sections[0])
            // ...
            // ShdrM (self.sections[M])
            // ShdrM+1 (.shstrtab)
            // EOF
            var serializer = std.io.Serializer(.Little, .Byte, @TypeOf(out_stream)).init(out_stream);
            var pos: u64 = 0;

            // add elf header
            //
            const header = headers.ElfHeader(elf_class) {
                .endian = self.endian,
                .abi = self.abi,
                .abi_version = self.abi_version,
                .obj_type = self.obj_type,
                .machine = self.machine,
                .entry = self.entry,
                .flags = self.flags,

                .phoff = self.phOffset(),
                .phnum = self.phNum(),

                .shoff = self.shOffset(),
                .shnum = self.shNum(),

                .shstrndx = self.shStrNdx(),
            };

            try serializer.serialize(header);
            pos += ElfHeader(elf_class).header_size;

            var seg_offset = self.segmentsOffset();

            // add segment headers
            //
            for (self.segments.toSlice()) |*segment| {
                const padding = calcAddrPadding(seg_offset, segment.vaddr, segment.alignment);
                const ph_header = ElfProgramHeader(elf_class) {
                    .ph_type = segment.ph_type,
                    .flags = segment.flags,
                    .offset = seg_offset + padding,
                    .vaddr = segment.vaddr,
                    .paddr = segment.paddr,
                    .filesz = segment.data.len,
                    .memsz = segment.memsz,
                    .align_ = segment.alignment,
                };
                try serializer.serialize(ph_header);
                segment._calculated_offset = pos;
                pos += ElfProgramHeader(elf_class).header_size;
                seg_offset += padding + segment.data.len;
            }

            // add segments
            //
            for (self.segments.toSlice()) |segment| {
                const alignment = segment.alignment;
                if (alignment > 1) {
                    // const padding = calcPadding(pos, alignment);
                    const padding = calcAddrPadding(pos, segment.vaddr, alignment);
                    try addPadding(&serializer, padding);
                    pos += padding;
                }
                try serializer.serialize(segment.data);
                pos += segment.data.len;
            }

            // add padding (if necessary) so that section headers are word aligned
            {
                const padding = calcPadding(pos, @This().elf_header_alignment);
                try addPadding(&serializer, padding);
                pos += padding;
            }

            if (self.numSections() == 0) {
                return;
            }

            assert(pos == self.shOffset());

            // add sh index 0
            if (self.hasShIndex0()) {
                const num_segs = self.numSegments();
                const ph_num = if (num_segs >= PN_XNUM) num_segs else 0;

                const num_secs = self.numSections();
                const sh_size = if (num_segs >= SHN_LORESERVE) num_secs else 0;

                const shstrndx = self.stringTableIndex();
                const strndx = if (shstrndx >= SHN_LORESERVE) shstrndx else 0;

                const sh_header = ElfSectionHeader(elf_class) {
                    .name = 0,
                    .sh_type = ElfShType.Null,
                    .flags = 0,
                    .addr = 0,
                    .offset = 0,
                    .size = sh_size,
                    .link = @intCast(u32, shstrndx),
                    .info = @intCast(u32, ph_num),
                    .addralign = 0,
                    .entsize = 0,
                };
                try serializer.serialize(sh_header);
                pos += ElfSectionHeader(elf_class).header_size;
            }

            // add section headers
            for (self.sections.toSlice()) |section| {
                const sh_header = ElfSectionHeader(elf_class) {
                    .name = 0,
                    .sh_type = section.sh_type,
                    .flags = section.flags,
                    .addr = section.addr,
                    .offset = 0,
                    .size = section.size,
                    .link = section.link,
                    .info = section.info,
                    .addralign = section.alignment,
                    .entsize = 0,
                };
                try serializer.serialize(sh_header);
                pos += ElfSectionHeader(elf_class).header_size;
            }

            // add .shstrtab
            if (false) { // (TODO)
                const sh_header = ElfSectionHeader(elf_class) {
                    .name = 0,
                    .sh_type = ElfShType.Null,
                    .flags = 0,
                    .addr = 0,
                    .offset = 0,
                    .size = 0,
                    .link = 0,
                    .info = 0,
                    .addralign = 0,
                    .entsize = 0,
                };
            }
        }
    };
}
