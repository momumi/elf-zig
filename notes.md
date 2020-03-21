
## References:

* https://refspecs.linuxfoundation.org/LSB_4.1.0/LSB-Core-generic/LSB-Core-generic/elf-generic.html
* https://refspecs.linuxfoundation.org/LSB_4.1.0/LSB-Core-AMD64/LSB-Core-AMD64/book1.html
* https://refspecs.linuxfoundation.org/
* http://www.muppetlabs.com/~breadbox/software/ELF.txt
* http://refspecs.linuxbase.org/elf/elf.pdf
* https://cirosantilli.com/elf-hello-world
* `man elf`

* http://michalmalik.github.io/elf-dynamic-segment-struggles
* https://reverseengineering.stackexchange.com/questions/2539/what-symbol-tables-stay-after-a-strip-in-elf-format
* https://www.technovelty.org/linux/plt-and-got-the-key-to-code-sharing-and-dynamic-libraries.html (global offset table (GOT) and procedure linkage table (PLT))

## Sections

* Each section occupies a contiguous array of memory in the file
* Sections can't overlap. Each byte in the file belongs to at most one section.
* If bytes in an ELF file are not referenced by any section or header, then there meaning is unspecified.

## Alignment in ELF files

### Header alignment

The program and section headers in the ELF file need to be word aligned. ie:

* 32-bit: alignment=0x04
* 64-bit: alignment=0x08

### Segment (page) alignment

When segments are loaded from an ELF file into memory, they are mmap-ed into
the file. This means that the `offset` of a segment in the ELF file must align
with the `virtual address` were the segment is loaded.

```
    (segment.offset % segment.alignment) == (segment.vaddr % segment.alignment)
```

eg: On Linux with 4kb pages `alignment = 0x1000`, so if a code segment has
`vaddr = 0x20080`, then that segment needs to be stored in the ELF file at an
offset with `0x__080`.


## Misc

* It seems like common practice for the ELF files to include one segment that
  loads the ELF program headers themselves into the processes memory. Not sure
  if there's a specific reason for this?
* The Linux ELF loader requires that that the program headers fit inside
  one 4kb page: [linux elf loader source](https://github.com/torvalds/linux/blob/v4.11/fs/binfmt_elf.c#L429).
* Lowest usable virtual memory address on linux is `0x10000`/64KiB
