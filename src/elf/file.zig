const std = @import("std");

const assert = std.debug.assert;

usingnamespace(@import("constants.zig"));
const headers = @import("headers.zig");
// const relocation = @import("relocation.zig");

const ArrayList = std.ArrayList;

// pub const constants = @import("constants.zig");
// pub const ElfClass = constants.ElfClass;

const ElfHeader = headers.ElfHeader;
const ElfProgramHeader = headers.ElfProgramHeader;
const ElfSectionHeader = headers.ElfSectionHeader;

const ShIndex = u32;
const PhIndex = u32;
const SymIndex = u32;
const RelIndex = u32;
const StrIndex = u32;

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

pub const SectionDataTypeTag = enum {
    None,
    SegmentIndex,
    Data,
    StringTable,
    SymbolTable,
    RelaTable,
};

pub fn SectionData(elf_class: ElfClass) type {
    return union(SectionDataTypeTag) {
        None: void,
        SegmentIndex: u32,
        Data: []const u8,
        StringTable: *const StringTable,
        SymbolTable: *const SymbolTable(elf_class),
        RelaTable: *const RelaTable(elf_class),
    };
}

pub fn Section(elf_class: ElfClass) type {
    return struct {
        const AddressType = elf_class.AddressType();
        const SectionDataType = SectionData(elf_class);

        name: StrIndex,
        sh_type: ElfShType,
        flags: AddressType,
        addr: AddressType,
        link: u32,
        info: u32,
        alignment: AddressType,
        entsize: AddressType,

        data: SectionDataType,
        // section_data =
        // segment_index: u32 = PN_XNUM,

        _data_offset: AddressType = 0,
        _data_size: AddressType = 0,

        pub fn getDataSize(self: @This()) AddressType {
            return switch (self.data) {
                .None, .SegmentIndex => 0,
                .Data => |data| data.len,
                .StringTable => |table| table.size(),
                .SymbolTable => |table| table.size(),
                .RelaTable => |table| table.size(),
            };
        }
    };
}

pub const StringTable = struct {
    data: ArrayList(u8),
    _offset: u64 = 0,

    pub fn init(alloc: *std.mem.Allocator) !StringTable {
        var result = StringTable {
            .data = ArrayList(u8).init(alloc),
        };

        try result.data.append('\x00');

        return result;
    }

    pub fn size(self: StringTable) usize {
        return self.data.len;
    }

    pub fn asSlice(self: StringTable) []const u8 {
        return self.data.span();
    }

    pub fn addString(self: *StringTable, string: []const u8) !StrIndex {
        var string_index = self.data.len;
        try self.data.appendSlice(string);
        try self.data.append('\x00');
        return @intCast(u32, string_index);
    }

    pub fn getString(self: StringTable, str_index: StrIndex) []const u8 {
        const span = self.data.span();
        const span_len = self.data.len;
        var str_len: u32 = 0;
        for (span[str_index..span_len]) |c| {
            if (c == '\x00') {
                break;
            }
            str_len += 1;
        }
        return span[str_index .. str_index+str_len];
    }
};

pub fn Symbol(elf_class: ElfClass) type {
    return struct {
        const AddressType = elf_class.AddressType();

        name: StrIndex,
        value: AddressType,
        size: AddressType,
        type_: headers.symtab.STT,
        bind: headers.symtab.STB,
        visbility: headers.symtab.STV,
        shndx: u32,
    };
}

pub fn SymbolTable(elf_class: ElfClass) type {
    return struct {
        const AddressType = elf_class.AddressType();
        const SymbolType = Symbol(elf_class);
        const ElfSymbolTableEntry = headers.symtab.ElfSymbolTableEntry(elf_class);
        const entry_size = ElfSymbolTableEntry.entry_size;

        symbol_entries: ArrayList(ElfSymbolTableEntry),

        _highest_local: u32 = 0,

        pub fn init(alloc: *std.mem.Allocator) !@This() {
            var result = @This() {
                .symbol_entries = ArrayList(ElfSymbolTableEntry).init(alloc),
            };

            // symtab entry at index 0
            const index0_symtab = SymbolType {
                .name = 0,
                .value = 0,
                .size = 0,
                .type_ = .NoType,
                .bind = .Local,
                .visbility = .Default,
                .shndx = 0,
            };
            _ = try result.addSymbol(index0_symtab);

            return result;
        }

        pub fn size(self: @This()) AddressType {
            return self.symbol_entries.len * @This().entry_size;
        }

        /// add a segment and return its index into the symbol table
        pub fn addSymbol(self: *@This(), symbol: SymbolType) !SymIndex {

            const entry = headers.symtab.ElfSymbolTableEntry(elf_class) {
                .name = symbol.name,
                .value = symbol.value,
                .size = symbol.size,
                .info = headers.symtab.stInfo(symbol.type_, symbol.bind),
                // visbility: symtab.STV, // TODO
                .other = 0,
                // TODO: this value needs special handling to use u32 values
                // need to add a SHT_SYMTAB_SHNDX section to store the extended
                // indices
                .shndx = @intCast(u16, symbol.shndx),
            };

            try self.symbol_entries.append(entry);

            const index = @intCast(SymIndex, self.symbol_entries.len-1);

            if (symbol.bind == .Local) {
                self._highest_local = index;
            }

            return index;
        }
    };
}

pub fn RelaTable(elf_class: ElfClass) type {
    return struct {
        const AddressType = elf_class.AddressType();
        const RelocationEntryType = headers.ElfRela(elf_class);
        const entry_size = RelocationEntryType.entry_size;

        rel_list: ArrayList(RelocationEntryType),

        pub fn init(alloc: *std.mem.Allocator) !@This() {
            var result = @This() {
                .rel_list = ArrayList(RelocationEntryType).init(alloc),
            };

            return result;
        }

        pub fn size(self: @This()) AddressType {
            return self.rel_list.len * @This().entry_size;
        }

        pub fn addRelocation(self: *@This(), relocation: RelocationEntryType) !RelIndex {
            try self.rel_list.append(relocation);
            return @intCast(RelIndex, self.rel_list.len-1);
        }
    };
}

pub fn ElfFile(elf_class: ElfClass) type {
    return struct {
        const AddressType = elf_class.AddressType();
        const SegmentType = Segment(elf_class);
        const SectionType = Section(elf_class);
        const SectionDataType = SectionData(elf_class);
        const SymbolTableType = SymbolTable(elf_class);
        const RelaTableType = RelaTable(elf_class);
        const elf_class: ElfClass = elf_class;

        /// All of the headers in the elf file should have this alignment
        const elf_header_alignment = elf_class.alignment();

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

        /// Offset into the ELF file where program headers will be stored
        _phdr_offset: AddressType = 0,
        /// Offset into the ELF file where the segment data will be stored
        _segment_data_offset: AddressType = 0,
        /// Offset into the ELF file where the section data will be stored
        _section_data_offset: AddressType = 0,
        /// Offset into the ELF file where section headers will be stored
        _shdr_offset: AddressType = 0,
        /// Section header index that contains the .shstrtab section
        _shstrtab_index: ShIndex = 0,

        pub fn init(
            endian: ElfEndian,
            abi: ElfAbi,
            abi_version: u8,
            obj_type: ElfObjType,
            machine: ElfMachine,
            entry: AddressType,
            flags: u32,
            alloc: *std.mem.Allocator
        ) !@This() {
            var result = @This() {
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

            // shdr index 0
            const index0_sec = Section(elf_class) {
                .name = 0,
                .sh_type = ElfShType.Null,
                .flags = 0,
                .addr = 0,
                .link = 0,
                .info = 0,
                .alignment = 0,
                .entsize = 0,
                .data =  SectionDataType { .None = {}, },
            };
            _ = try result.addSection(index0_sec);

            return result;
        }

        /// add a segment and return its index into the program header table
        pub fn addSegment(self: *@This(), segment: SegmentType) !u32 {
            try self.segments.append(segment);
            return @intCast(u32, self.segments.len-1);
        }

        /// add a segment and return its index into the section header table
        pub fn addSection(self: *@This(), section: SectionType) !PhIndex {
            try self.sections.append(section);
            return @intCast(PhIndex, self.sections.len-1);
        }

        fn addShStrTab(self: *@This(), strtab: *StringTable) !ShIndex {
            // add .shstrtab
            const name = try strtab.addString(".shstrtab");

            self._shstrtab_index = try self.addStringTable(name, strtab);
            return self._shstrtab_index;
        }

        fn addStringTable(self: *@This(), name: StrIndex, strtab: *StringTable) !ShIndex {
            const header = Section(elf_class) {
                .name = name,
                .sh_type = ElfShType.StrTab,
                .flags = 0,
                .addr = 0,
                .link = 0,
                .info = 0,
                .alignment = 1,
                .entsize = 0,
                .data = SectionDataType { .StringTable = strtab, },
            };
            return try self.addSection(header);
        }

        fn addSymbolTable(
            self: *@This(),
            name: StrIndex,
            symtab: *const SymbolTableType,
            strtab_index: ShIndex,
        ) !ShIndex {
            // TODO: if the symbol table has more than u16 entries need to add
            // a SHT_SYMTAB_SHNDX section to store the extended indices
            //
            const symtab_sh = Section(elf_class) {
                .name = name,
                .sh_type = .SymTab,
                .flags = 0,
                .addr = 0,
                .link = strtab_index,
                .info = symtab._highest_local + 1,
                .alignment = elf_class.alignment(),
                .entsize = SymbolTableType.entry_size,
                .data = SectionDataType { .SymbolTable = symtab, },
            };
            const symtab_sh_index = try self.addSection(symtab_sh);

            return symtab_sh_index;
        }

        fn addRelaTable(
            self: *@This(),
            name: StrIndex,
            rela_table: *const RelaTableType,
            /// the assosicated symbol table for relocations
            symtab_index: ShIndex,
            /// the section to which the relocations apply
            section_index: ShIndex,
        ) !ShIndex {
            const rela_sh = Section(elf_class) {
                .name = name,
                .sh_type = .Rela,
                .flags = 0,
                .addr = 0,
                .link = symtab_index,
                .info = section_index,
                .alignment = elf_class.alignment(),
                .entsize = RelaTableType.entry_size,
                .data = SectionDataType { .RelaTable = rela_table, },
            };
            return try self.addSection(rela_sh);

        }

        /// Offset into the ELF file where the ELF header itself will be stored
        ///
        /// The elf header is always at the start of the file
        fn elfHeaderOffset(self: @This()) AddressType {
            return 0;
        }

        /// Offset into the ELF file where program headers will be stored
        ///
        /// Program headers are stored after the elf header
        fn calcPhOffset(self: @This()) AddressType {
            if (self.numSegments() == 0) {
                return 0;
            } else {
                return self.elfHeaderOffset() + ElfHeader(elf_class).header_size;
            }
        }

        fn calcSegmentDataOffset(self: *@This()) AddressType {
            // find the size of all the program headers and where they end
            const ph_num = self.numSegments();
            const ph_size = ElfProgramHeader(elf_class).header_size;
            const ph_total_size = ph_num * ph_size;
            const ph_list_end = self.calcPhOffset() + ph_total_size;

            // find out the necessary alignment for the first segment
            const segment = self.segments.span()[0];
            const padding = calcAddrPadding(ph_list_end, segment.vaddr, segment.alignment);

            return ph_list_end + padding;
        }

        fn segmentDataTotalSize(self: @This()) AddressType {
            var seg_base_offset = self._segment_data_offset;
            var size: u64 = 0;
            for (self.segments.span()) |segment| {
                const alignment = segment.alignment;
                const seg_offset = seg_base_offset + size;
                const padding = calcAddrPadding(seg_offset, segment.vaddr, alignment);
                size += segment.data.len + padding;
            }
            return size;
        }

        fn calcSectionDataOffset(self: *@This()) AddressType {
            if (self.numSections() == 0) {
                return 0;
            }

            var pos = self._segment_data_offset;
            pos += self.segmentDataTotalSize();

            const data_alignment = self.sections.span()[0].alignment;
            const padding = calcPadding(pos, data_alignment);
            pos += padding;

            return pos;
        }

        fn sectionDataTotalSize(self: @This()) AddressType {
            var base_addr = self._section_data_offset;
            var size: u64 = 0;
            for (self.sections.span()) |section| {
                // ignore segments that don't carry any data of there own
                switch (section.data) {
                    .None, .SegmentIndex => continue,
                    else => {},
                }

                // calculate how much padding is needed for the section data
                const alignment = section.alignment;
                const sec_offset = base_addr + size;
                const padding = calcPadding(sec_offset, alignment);

                size += section.getDataSize() + padding;
            }
            return size;
        }

        fn calcShOffset(self: @This()) AddressType {
            if (self.numSections() == 0) {
                return 0;
            }

            var pos = self._section_data_offset;
            pos += self.sectionDataTotalSize();

            const shdr_alignment = @This().elf_header_alignment;
            pos += calcPadding(pos, shdr_alignment);

            return pos;
        }

        fn calcOffsets(self: *@This()) void {
            self._phdr_offset = self.calcPhOffset();
            self._segment_data_offset = self.calcSegmentDataOffset();
            self._section_data_offset = self.calcSectionDataOffset();
            self._shdr_offset = self.calcShOffset();
        }

        /// Offset into the ELF file where section headers will be stored
        ///
        /// Section headers are stored after all the segments
        fn shOffset(self: @This()) u64 {
            if (self.numSections() == 0) {
                return 0;
            }

            return self._shdr_offset;
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

        fn numSegments(self: @This()) AddressType {
            if (self.segments.len == 0) {
                return 0;
            }

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
            return self.sections.len > 1;
        }

        fn hasStrTab(self: @This()) bool {
            return self.symbols.len > 1;
        }

        fn hasSymTab(self: @This()) bool {
            return self.symbols.len > 1;
        }

        fn numSections(self: @This()) AddressType {
            // if the len == 1, then we only have the 0 index which is just a
            // dummy entry. In that case we don't need any sections
            if (self.sections.len <= 1) {
                return 0;
            } else {
                return @intCast(AddressType, self.sections.len);
            }
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

        fn shStrTabShIndex(self: @This()) ShIndex {
            return self._shstrtab_index;
        }

        /// Value of shstrndx in the ELF header
        fn shStrNdx(self: @This()) u16 {
            const num_sections = self.numSections();
            if (num_sections <= 1) {
                return 0;
            }

            const shstrndx = self.shStrTabShIndex();
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

                .phoff = self._phdr_offset,
                .phnum = self.phNum(),

                .shoff = self._shdr_offset,
                .shnum = self.shNum(),

                .shstrndx = self.shStrNdx(),
            };

            try serializer.serialize(header);
            pos += ElfHeader(elf_class).header_size;

            return pos;
        }

        fn addProgramHeaders(self: @This(), serializer: var, cur_offset: u64) !u64 {
            var pos = cur_offset;
            var seg_offset = self._segment_data_offset;

            // add segment headers
            //
            for (self.segments.span()) |*segment| {
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

            for (self.segments.span()) |segment| {
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

        fn addSectionData(self: *@This(), serializer: var, cur_offset: u64) !u64 {
            var pos = cur_offset;

            // add padding (if necessary) for section data
            {
                const alignment = self.sections.span()[0].alignment;
                const padding = calcPadding(pos, alignment);
                pos += try addPadding(serializer, padding);
            }

            assert(pos == self._section_data_offset);

            // add data for sections
            for (self.sections.span()) |*section| {
                switch (section.data) {
                    .None => {
                        section._data_offset = 0;
                        section._data_size = 0;
                    },

                    .SegmentIndex => |index| {
                        const segment = self.segments.span()[index];
                        section._data_offset = segment._segment_offset;
                        section._data_size = segment.data.len;
                    },

                    .StringTable, .SymbolTable, .RelaTable, .Data => {
                        const padding = calcPadding(pos, section.alignment);
                        pos += try addPadding(serializer, padding);

                        // save the position of this data for later
                        section._data_offset = pos;
                        section._data_size = section.getDataSize();

                        switch (section.data) {
                            .None, .SegmentIndex => unreachable,

                            .Data => |data| {
                                try serializer.serialize(data);
                            },

                            .StringTable => |str_tab| {
                                try serializer.serialize(str_tab.asSlice());
                            },

                            .SymbolTable => |sym_tab| {
                                try serializer.serialize(sym_tab.symbol_entries.span());
                            },

                            .RelaTable => |rela_tab| {
                                try serializer.serialize(rela_tab.rel_list.span());
                            },
                        }
                        pos += section._data_size;
                    },
                }

            }

            return pos;
        }

        fn addSectionHeaders(self: @This(), serializer: var, cur_offset: u64) !u64 {
            var pos = cur_offset;

            // add padding (if necessary) so that section headers are word aligned
            {
                const padding = calcPadding(pos, @This().elf_header_alignment);
                pos += try addPadding(serializer, padding);
            }

            assert(pos == self._shdr_offset);

            // fill in section header index0
            {
                const sh_header0 = &self.sections.span()[0];

                const num_segs = self.numSegments();
                if (num_segs >= PN_XNUM) {
                    sh_header0.info = @intCast(u32, num_segs);
                }

                const num_secs = self.numSections();
                if (num_secs >= SHN_LORESERVE) {
                    sh_header0._data_size = num_secs;
                }

                const shstrtab_ndx = self.shStrTabShIndex();
                if (shstrtab_ndx >= SHN_LORESERVE) {
                    sh_header0.link = @intCast(u32, shstrtab_ndx);
                }

            }

            // add section headers
            for (self.sections.span()) |section| {
                const sh_header = ElfSectionHeader(elf_class) {
                    .name = section.name,
                    .sh_type = section.sh_type,
                    .flags = section.flags,
                    .addr = section.addr,
                    .offset = section._data_offset,
                    .size = section._data_size,
                    .link = section.link,
                    .info = section.info,
                    .addralign = section.alignment,
                    .entsize = section.entsize,
                };
                try serializer.serialize(sh_header);
                pos += ElfSectionHeader(elf_class).header_size;
            }

            return pos;
        }

        /// Write this ELF file to the provided OutStream
        pub fn write(self: *@This(), out_stream: var) !void {
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
            // section[0].data
            // ...
            // section[M].data
            //
            // Shdr[0] (self.sections[0])
            // ...
            // Shdr[M] (self.sections[M])
            //
            // EOF
            var serializer = std.io.Serializer(.Little, .Byte, @TypeOf(out_stream)).init(out_stream);
            var pos: u64 = 0;

            self.calcOffsets();

            pos = try self.addElfHeader(&serializer, pos);

            if (self.numSegments() > 0) {
                pos = try self.addProgramHeaders(&serializer, pos);
                pos = try self.addSegments(&serializer, pos);
            }

            if (self.numSections() > 0) {
                pos = try self.addSectionData(&serializer, pos);
                pos = try self.addSectionHeaders(&serializer, pos);
            }
        }
    };
}
