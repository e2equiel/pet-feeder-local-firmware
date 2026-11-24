"""Verify ELF format and dynamic imports without distributing vendor binaries.

python tools/check_imports.py build/pf_local.so --allowed tools/target-imports.txt
python tools/check_imports.py build/pf_local.so /path/to/your/private/libuClibc.so
Requires pyelftools. The installer also checks eager loading on the actual feeder.
"""
import argparse
from pathlib import Path
from elftools.elf.elffile import ELFFile


def symbols(path, undefined):
    with open(path, "rb") as source:
        elf=ELFFile(source)
        if undefined and (elf.elfclass != 32 or elf['e_machine'] != 'EM_ARM' or not elf.little_endian
                          or elf['e_flags'] & 0x400 or not elf.get_section_by_name('.hash')
                          or not elf.get_section_by_name('.gnu.hash')):
            raise SystemExit('Expected ARM32 little-endian soft-float with both SysV and GNU symbol hashes')
        return {symbol.name for symbol in elf.get_section_by_name('.dynsym').iter_symbols()
                if symbol.name and (symbol['st_shndx']=='SHN_UNDEF')==undefined}

parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('module',type=Path)
parser.add_argument('private_libc',type=Path,nargs='?')
parser.add_argument('--allowed',type=Path)
args=parser.parse_args()
if args.allowed:
    allowed={line.strip() for line in args.allowed.read_text().splitlines() if line.strip() and not line.startswith('#')}
elif args.private_libc:
    allowed=symbols(args.private_libc,False)
else:
    parser.error('Pass --allowed or your own private libc path')
missing=symbols(args.module,True)-allowed
if missing:
    raise SystemExit('Unsupported dynamic imports: '+', '.join(sorted(missing)))
print('ELF ABI and dynamic imports match the supported target profile')
