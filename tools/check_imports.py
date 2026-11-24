"""Reject preload imports absent from a privately extracted target libc.

Usage: python check_imports.py path/to/pf_local.so path/to/libuClibc.so
Requires pyelftools. Never commit the target's firmware dump or libraries.
"""
import sys
from elftools.elf.elffile import ELFFile


def symbols(path, undefined):
    with open(path, "rb") as source:
        return {
            symbol.name
            for symbol in ELFFile(source).get_section_by_name(".dynsym").iter_symbols()
            if symbol.name and (symbol["st_shndx"] == "SHN_UNDEF") == undefined
        }


missing = symbols(sys.argv[1], True) - symbols(sys.argv[2], False)
if missing:
    raise SystemExit("Unsupported dynamic imports: " + ", ".join(sorted(missing)))
print("All dynamic imports are provided by the target libc")
