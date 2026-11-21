#!/usr/bin/env python3
"""Build MG.COM: the program (mg.asm) followed by its built-in editor (mged.asm).

The editor is assembled to run at WIN, the start of MG's list memory, and is
read from the end of MG.COM when a text file is opened (see edl_load in
mg.asm). Needs pyz80 (pip install pyz80) on the PATH.
"""
import os, pickle, re, subprocess, sys
HERE = os.path.dirname(os.path.abspath(__file__)); os.chdir(HERE)
os.makedirs('build', exist_ok=True)

def asm(src, obj, sym=None):
    cmd = ['pyz80', '--obj=' + obj] + (['--exportfile=' + sym] if sym else []) + [src]
    out = subprocess.run(cmd, capture_output=True, text=True)
    text = out.stdout + out.stderr
    if 'error' in text.lower() or out.returncode:
        sys.exit('%s:\n%s' % (src, text))

asm('mg.asm', 'build/mg_main.bin', 'build/mg.sym')
sym = pickle.load(open('build/mg.sym', 'rb'))
own = {m.group(1).upper() for m in re.finditer(r'^([A-Za-z_][A-Za-z0-9_]*):', open('mged.asm').read(), re.M)}
with open('build/mgsyms.inc', 'w') as f:
    f.write('; symbols of mg.asm for mged.asm (made by build.py)\n')
    for k, v in sorted(sym.items()):
        if k.upper() not in own and re.match(r'^[A-Za-z_][A-Za-z0-9_]*$', k):
            f.write('%s: equ 0x%04X\n' % (k, v & 0xFFFF))
asm('mged.asm', 'build/mged.bin', 'build/mged.sym')

g = {k.upper(): v for k, v in sym.items()}
e = {k.upper(): v for k, v in pickle.load(open('build/mged.sym', 'rb')).items()}
main = open('build/mg_main.bin', 'rb').read()
ed = open('build/mged.bin', 'rb').read()
assert len(main) == g['ED_FOFS'], 'the editor must start at ED_FOFS'
assert len(ed) <= g['ED_MAX'], 'editor larger than ED_MAX'
assert e['ED_TXT'] + 0x400 < g['POOL'] and g['OVB'] >= g['IDX'], 'editor buffers reach the name pool (selname)'
open('MG.COM', 'wb').write(main + ed)
print('MG.COM %d bytes (program %d + editor %d); TPA top for the list %04Xh, for ZIP extraction %04Xh'
      % (len(main) + len(ed), len(main), len(ed), g['MEM_END'] + 0x300, g['INFL_END'] + 0x200))
