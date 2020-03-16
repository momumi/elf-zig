const std = @import("std");

const assert = std.debug.assert;

usingnamespace(@import("constants.zig"));
pub const headers = @import("headers.zig");

const symtab = headers.symtab;

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

        _segment_offset: u64 = undefined,
    };
}

pub fn Section(elf_class: ElfClass) type {
    return struct {
        const AddressType = elf_class.AddressType();

        name: [:0]const u8,
        sh_type: ElfShType,
        flags: AddressType,
        segment_index: u32,
        addr: AddressType,
        link: u32,
        info: u32,
        size: AddressType,
        alignment: AddressType,

        _name_offset: u32 = 0,
    };
}

pub fn Symbol(elf_class: ElfClass) type {
    return struct {
        const AddressType = elf_class.AddressType();

        name: [:0]const u8,
        value: AddressType,
        size: AddressType,
        type_: symtab.STT,
        bind: symtab.STB,
        visbility: symtab.STV,
        shndx: u16,

        _name_offset: u32 = 0,
    };
}

pub fn ElfFile(elf_class: ElfClass) type {
    return struct {
        const AddressType = elf_class.AddressType();
        const SegmentType = Segment(elf_class);
        const SectionType = Section(elf_class);
        const SymbolType = Symbol(elf_class);
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
        symbols: ArrayList(SymbolType),

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
                .symbols = ArrayList(SymbolType).init(alloc),
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
            if (self.numSegments() == 0) {
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
            if (self.numSegments() == 0) {
                return 0;
            }

            // find the size of all the program headers and where they end
            const ph_num = self.numSegments();
            const ph_size = ElfProgramHeader(elf_class).header_size;
            const ph_total_size = ph_num * ph_size;
            const ph_list_end = self.phOffset() + ph_total_size;

            // find out the necessary alignment for the first segment
            const segment = self.segments.at(0);
            const padding = calcAddrPadding(ph_list_end, segment.vaddr, segment.alignment);

            return ph_list_end + padding;
        }

        fn segmentsTotalSize(self: @This()) u64 {
            var seg_base_offset = self.segmentsOffset();
            var size: u64 = 0;
            for (self.segments.toSlice()) |segment| {
                const alignment = segment.alignment;
                const seg_offset = seg_base_offset + size;
                const padding = calcAddrPadding(seg_offset, segment.vaddr, alignment);
                size += segment.data.len + padding;
            }
            return size;
        }

        //                        0   1        10  11     18  19
        const shstrtab_default = "\x00.shstrtab\x00.strtab\x00.symtab\x00";
        const strtab_default = "\x00";
        const shstrtab_name_offset = 1;
        const strtab_name_offset = 11;
        const symtab_name_offset = 19;

        const shstrtab_sh_index: u32 = 1;
        const strtab_sh_index: u32 = 2;
        const symtab_sh_inndx: u32 = 3;

        fn stringTableSizeCommon(self: @This(), container: var) u64 {
            var size: u64 = 0;

            for (container.toSlice()) |item| {
                if (item.name.len == 0) {
                    continue;
                }
                // +1 for null terminator
                size += item.name.len + 1;
            }

            return size;
        }

        fn shStrTabSize(self: @This()) u64 {
            if (self.numSections() == 0) {
                return 0;
            }

            var size = shstrtab_default.len;
            size += self.stringTableSizeCommon(self.sections);

            return size;
        }

        /// Offset into the ELF file for .shstrtab
        fn shStrTabOffset(self: @This()) u64 {
            if (self.numSections() == 0) {
                return 0;
            }

            var pos = self.segmentsOffset();
            pos += self.segmentsTotalSize();

            return pos;
        }

        fn numSymbols(self: @This()) u64 {
            if (self.symbols.len == 0) {
                return 0;
            } else {
                return self.symbols.len + 1;
            }
        }

        /// Size of .strtab
        fn strTabSize(self: @This()) u64 {
            if (self.numSymbols() == 0) {
                return 0;
            }

            var size = strtab_default.len;
            size += self.stringTableSizeCommon(self.symbols);

            return size;
        }

        /// Offset into the ELF file for .strtab
        fn strTabOffset(self: @This()) u64 {
            var pos = self.shStrTabOffset();
            pos += self.shStrTabSize();
            return pos;
        }

        /// Size of the .symtab
        fn symTabSize(self: @This()) u64 {
            return self.numSymbols() * symtab.ElfSymbolTableEntry(elf_class).entry_size;
        }

        /// Offset into the ELF file for .symtab
        fn symTabOffset(self: @This()) u64 {
            var pos = self.strTabOffset();
            pos += self.strTabSize();
            return pos;
        }

        /// Offset into the ELF file where section headers will be stored
        ///
        /// Section headers are stored after all the segments
        fn shOffset(self: @This()) u64 {
            if (self.numSections() == 0) {
                return 0;
            }

            var pos = self.symTabOffset();
            pos += self.symTabSize();

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

        fn addPadding(serializer: var, num_bytes: u64) !u64 {
            var i: usize = 0;
            const zero: u8 = 0;
            while (i < num_bytes) : (i += 1) {
                try serializer.serializeInt(zero);
            }
            return num_bytes;
        }

        const PN_XNUM = 0xffff;

        const SHN_LORESERVE = 0xff00;
        const SHN_XINDEX = 0xffff;

        fn numSegments(self: @This()) AddressType {
            if (self.segments.len == 0) {
                return 0;
            }

            return self.segments.len + 1;
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

        fn hasStrTab(self: @This()) bool {
            return self.symbols.len > 0;
        }

        fn hasSymTab(self: @This()) bool {
            return self.symbols.len > 0;
        }

        fn hasShIndex0(self: @This()) bool {
            return (
                (self.sections.len > 0)
                or (self.phNum() == PN_XNUM)
            );
        }

        fn numSections(self: @This()) AddressType {
            var num_sections = @intCast(AddressType, self.sections.len);
            num_sections += @bitCast(u1, self.hasShIndex0());
            num_sections += @bitCast(u1, self.hasShStrTab());
            num_sections += @bitCast(u1, self.hasStrTab());
            num_sections += @bitCast(u1, self.hasSymTab());
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

        fn shStrTabIndex(self: @This()) u32 {
            const num_sections = self.numSections();
            if (num_sections == 0) {
                return 0;
            } else {
                return shstrtab_name_offset;
            }
        }

        fn  strTabIndex(self: @This()) u32 {
            const num_sections = self.numSections();
            if (num_sections == 0) {
                return 0;
            } else {
                return strtab_name_offset;
            }
        }

        fn symbolTableIndex(self: @This()) u32 {
            const num_sections = self.numSections();
            if (num_sections == 0) {
                return 0;
            } else {
                return symtab_name_offset;
            }
        }

        /// Value of shstrndx in the ELF header
        fn shStrNdx(self: @This()) u16 {
            const num_sections = self.numSections();
            if (num_sections == 0) {
                return 0;
            }

            const shstrndx = self.shStrTabIndex();
            if (shstrndx >= SHN_LORESERVE) {
                return SHN_XINDEX;
            } else {
                return @intCast(u16, shstrndx);
            }
        }

        fn addElfHeader(self: @This(), serializer: var, cur_offset: u64) !u64 {
            var pos = cur_offset;

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

            return pos;
        }

        fn addProgramHeaders(self: @This(), serializer: var, cur_offset: u64) !u64 {
            var pos = cur_offset;
            var seg_offset = self.segmentsOffset();

            // segment header index 0
            {
                const ph_header = ElfProgramHeader(elf_class) {
                    .ph_type = .Null,
                    .flags = 0,
                    .offset = 0,
                    .vaddr = 0,
                    .paddr = 0,
                    .filesz = 0,
                    .memsz = 0,
                    .align_ = 0,
                };
                try serializer.serialize(ph_header);
                pos += ElfProgramHeader(elf_class).header_size;
            }

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
                segment._segment_offset = ph_header.offset;
                pos += ElfProgramHeader(elf_class).header_size;
                seg_offset += padding + segment.data.len;
            }

            return pos;
        }

        fn addSegments(self: @This(), serializer: var, cur_offset: u64) !u64 {
            var pos = cur_offset;

            for (self.segments.toSlice()) |segment| {
                const alignment = segment.alignment;
                if (alignment > 1) {
                    // const padding = calcPadding(pos, alignment);
                    const padding = calcAddrPadding(pos, segment.vaddr, alignment);
                    pos += try addPadding(serializer, padding);
                }
                try serializer.serialize(segment.data);
                pos += segment.data.len;
            }

            return pos;
        }

        fn stringTableCommon(
            self: @This(),
            default_strings: []const u8,
            arrayNames: var,
            serializer: var,
            cur_offset: u64
        ) !u64 {
            const str_tab_base = cur_offset;
            var pos = cur_offset;

            // first byte of string table must be null terminator
            try serializer.serialize(default_strings);
            pos += default_strings.len;

            for (arrayNames.toSlice()) |*item| {
                if (item.name.len == 0) {
                    item._name_offset = 0;
                    continue;
                }

                item._name_offset = @intCast(u32, pos - str_tab_base);

                try serializer.serialize(item.name);
                pos += item.name.len;
                pos += try addPadding(serializer, 1);
            }

            return pos;
        }

        fn addShStringTable(self: @This(), serializer: var, cur_offset: u64) !u64 {
            if (!self.hasShStrTab()) {
                return cur_offset;
            }
            assert(cur_offset == self.shStrTabOffset());
            return self.stringTableCommon(shstrtab_default, self.sections, serializer, cur_offset);
        }

        fn addSymTabStringTable(self: @This(), serializer: var, cur_offset: u64) !u64 {
            if (!self.hasStrTab()) {
                return cur_offset;
            }
            assert(cur_offset == self.strTabOffset());
            return self.stringTableCommon(strtab_default, self.symbols, serializer, cur_offset);
        }

        fn addSymTab(
            self: @This(),
            serializer: var,
            cur_offset: u64,
            highest_local: *u32,
        ) !u64 {
            if (!self.hasSymTab()) {
                return cur_offset;
            }

            const entry_size = symtab.ElfSymbolTableEntry(elf_class).entry_size;
            var pos = cur_offset;

            assert(pos == self.symTabOffset());
            {
                const entry_index0 = symtab.ElfSymbolTableEntry(elf_class) {
                    .name = 0,
                    .value = 0,
                    .size = 0,
                    .info = 0,
                    .other = 0,
                    .shndx = 0,
                };

                try serializer.serialize(entry_index0);
                pos += entry_size;
            }

            highest_local.* = 0;

            for (self.symbols.toSlice()) |symbol, i| {
                if (symbol.bind == .Local) {
                    highest_local.* = @intCast(u32, i)+2;
                }
                const entry = symtab.ElfSymbolTableEntry(elf_class) {
                    .name = symbol._name_offset,
                    .value = symbol.value,
                    .size = symbol.size,
                    .info = symtab.stInfo(symbol.type_, symbol.bind),
                    .other = 0,
                    .shndx = symbol.shndx,
                    // visbility: symtab.STV,
                };

                try serializer.serialize(entry);
                pos += entry_size;
            }

            return pos;
        }

        fn addSectionHeaders(self: @This(), serializer: var, cur_offset: u64, highest_local: u32) !u64 {
            var pos = cur_offset;

            // add padding (if necessary) so that section headers are word aligned
            {
                const padding = calcPadding(pos, @This().elf_header_alignment);
                pos += try addPadding(serializer, padding);
            }

            assert(pos == self.shOffset());

            // add sh index 0
            if (self.hasShIndex0()) {
                const num_segs = self.numSegments();
                const ph_num = if (num_segs >= PN_XNUM) num_segs else 0;

                const num_secs = self.numSections();
                const sh_size = if (num_secs >= SHN_LORESERVE) num_secs else 0;

                const shstrtab_ndx = shstrtab_sh_index;
                const link_str_tab_ndx = if (shstrtab_ndx >= SHN_LORESERVE) shstrtab_ndx else 0;

                const sh_header = ElfSectionHeader(elf_class) {
                    .name = 0,
                    .sh_type = ElfShType.Null,
                    .flags = 0,
                    .addr = 0,
                    .offset = 0,
                    .size = sh_size,
                    .link = @intCast(u32, link_str_tab_ndx),
                    .info = @intCast(u32, ph_num),
                    .addralign = 0,
                    .entsize = 0,
                };
                try serializer.serialize(sh_header);
                pos += ElfSectionHeader(elf_class).header_size;
            }

            // add .shstrtab
            if (self.hasShStrTab()) {
                const sh_header = ElfSectionHeader(elf_class) {
                    .name = self.shStrTabIndex(),
                    .sh_type = ElfShType.StrTab,
                    .flags = 0,
                    .addr = 0,
                    .offset = self.shStrTabOffset(),
                    .size = self.shStrTabSize(),
                    .link = 0,
                    .info = 0,
                    .addralign = 1,
                    .entsize = 0,
                };
                try serializer.serialize(sh_header);
                pos += ElfSectionHeader(elf_class).header_size;
            }

            // add .strtab
            if (self.hasStrTab()) {
                const sh_header = ElfSectionHeader(elf_class) {
                    .name = self.strTabIndex(),
                    .sh_type = ElfShType.StrTab,
                    .flags = 0,
                    .addr = 0,
                    .offset = self.strTabOffset(),
                    .size = self.strTabSize(),
                    // .link = self.strTabShIndex(),
                    .link = 0,
                    .info = 0,
                    .addralign = 1,
                    .entsize = 0,
                };
                try serializer.serialize(sh_header);
                pos += ElfSectionHeader(elf_class).header_size;
            }

            // add .symtab
            if (self.hasSymTab()) {
                const sh_header = ElfSectionHeader(elf_class) {
                    .name = self.symbolTableIndex(),
                    .sh_type = ElfShType.SymTab,
                    .flags = 0,
                    .addr = 0,
                    .offset = self.symTabOffset(),
                    .size = self.symTabSize(),
                    .link = strtab_sh_index,
                    .info = highest_local,
                    .addralign = 1,
                    .entsize = symtab.ElfSymbolTableEntry(elf_class).entry_size,
                };
                try serializer.serialize(sh_header);
                pos += ElfSectionHeader(elf_class).header_size;
            }

            // add section headers
            for (self.sections.toSlice()) |section| {
                const sh_header = ElfSectionHeader(elf_class) {
                    .name = section._name_offset,
                    .sh_type = section.sh_type,
                    .flags = section.flags,
                    .addr = section.addr,
                    .offset = self.segments.at(section.segment_index)._segment_offset,
                    .size = section.size,
                    .link = section.link,
                    .info = section.info,
                    .addralign = section.alignment,
                    .entsize = 0,
                };
                try serializer.serialize(sh_header);
                pos += ElfSectionHeader(elf_class).header_size;
            }

            return pos;
        }

        /// Write this ELF file to the provided OutStream
        pub fn write(self: @This(), out_stream: var) !void {
            // Layout of how we will write the ELF file:
            //
            // ELF header
            //
            // Phdr0 (self.segment[0])
            // ...
            // PhdrN (self.segment[N])
            //
            // Segments0 (self.segment[0].data)
            // ...
            // SegmentsN (self.segment[N].data)
            //
            // ShStringTable (.shstrtab)
            // SymtabStringTable (.strtab)
            // ShSymbolTable (.symtab)
            //
            // Shdr[0] (Index0 Shdr SHT_NULL)
            // Shdr[1] (.shstrtab)
            // Shdr[2] (.strtab)
            // Shdr[3] (.symtab)
            // Shdr[4] (self.sections[0])
            // ...
            // Shdr[M+5] (self.sections[M])
            //
            // EOF
            var serializer = std.io.Serializer(.Little, .Byte, @TypeOf(out_stream)).init(out_stream);
            var pos: u64 = 0;

            pos = try self.addElfHeader(&serializer, pos);

            if (self.numSegments() > 0) {
                pos = try self.addProgramHeaders(&serializer, pos);
                pos = try self.addSegments(&serializer, pos);
            }

            if (self.numSections() > 0) {
                pos = try self.addShStringTable(&serializer, pos);
                pos = try self.addSymTabStringTable(&serializer, pos);
                var highest_local: u32 = 0;
                pos = try self.addSymTab(&serializer, pos, &highest_local);
                pos = try self.addSectionHeaders(&serializer, pos, highest_local);
            }
        }
    };
}
