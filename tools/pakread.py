#!/usr/bin/env python3
"""Minimal reader for UE4 pak v8 (4.22-4.24), unencrypted index. List and extract files. Read-only on the pak."""
import struct, sys, zlib, os, fnmatch

def rstr(f):
    n = struct.unpack('<i', f.read(4))[0]
    if n == 0: return ''
    if n < 0:
        return f.read(-n * 2).decode('utf-16-le').rstrip('\x00')
    return f.read(n).decode('latin-1').rstrip('\x00')

def open_pak(path):
    f = open(path, 'rb')
    f.seek(0, 2); size = f.tell()
    for tail in range(200, 400):
        f.seek(size - tail); b = f.read(4)
        if b == b'\xe1\x12\x6f\x5a':
            magic_pos = size - tail
            break
    else:
        raise SystemExit('pak magic not found')
    f.seek(magic_pos - 1); enc = f.read(1)[0]
    f.seek(magic_pos + 4)
    version, idx_off, idx_size = struct.unpack('<iqq', f.read(20))
    f.read(20)
    names = []
    rest = size - f.tell()
    for _ in range(rest // 32):
        names.append(f.read(32).split(b'\x00')[0].decode())
    return f, version, enc, idx_off, idx_size, names

def read_entry(f, version):
    off, sz, usz = struct.unpack('<qqq', f.read(24))
    cmeth = struct.unpack('<I', f.read(4))[0]
    f.read(20)
    blocks = []
    if cmeth != 0:
        n = struct.unpack('<i', f.read(4))[0]
        for _ in range(n):
            blocks.append(struct.unpack('<qq', f.read(16)))
    flags = f.read(1)[0]
    bsize = struct.unpack('<I', f.read(4))[0]
    return dict(off=off, size=sz, usize=usz, cmeth=cmeth, blocks=blocks, flags=flags, bsize=bsize)

def index(path):
    f, version, enc, idx_off, idx_size, names = open_pak(path)
    if enc: raise SystemExit('encrypted index')
    f.seek(idx_off)
    mount = rstr(f)
    count = struct.unpack('<i', f.read(4))[0]
    entries = {}
    for _ in range(count):
        name = rstr(f)
        entries[name] = read_entry(f, version)
    return f, version, mount, entries, names

def extract(f, e, names):
    if e['flags'] & 1: raise RuntimeError('encrypted entry')
    if e['cmeth'] == 0:
        # data follows a copy of the entry header
        f.seek(e['off'])
        hdr = read_entry(f, 8)
        return f.read(e['usize'])
    meth = (names[e['cmeth'] - 1] or 'zlib').lower()
    if meth != 'zlib': raise RuntimeError('compression ' + meth)
    out = bytearray()
    for (s, t) in e['blocks']:
        f.seek(e['off'] + s)   # v8: block offsets relative to the entry
        out += zlib.decompress(f.read(t - s))
    return bytes(out[:e['usize']])

if __name__ == '__main__':
    pak, cmd = sys.argv[1], sys.argv[2]
    f, version, mount, entries, names = index(pak)
    if cmd == 'info':
        print('version', version, 'mount', mount, 'files', len(entries), 'compression', names)
    elif cmd == 'list':
        pat = sys.argv[3] if len(sys.argv) > 3 else '*'
        for n, e in entries.items():
            if fnmatch.fnmatch(n.lower(), pat.lower()): print(e['usize'], n)
    elif cmd == 'extract':
        outdir, pats = sys.argv[3], sys.argv[4:]
        k = 0
        for n, e in entries.items():
            if any(fnmatch.fnmatch(n.lower(), p.lower()) for p in pats):
                data = extract(f, e, names)
                dst = os.path.join(outdir, n)
                os.makedirs(os.path.dirname(dst), exist_ok=True)
                open(dst, 'wb').write(data); k += 1
        print('extracted', k)
