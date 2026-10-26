#!/usr/bin/env python3
"""Read cooked UE 4.23 Blueprint packages (.uasset + .uexp) and disassemble their Kismet bytecode.

Usage:
  kismet.py <asset.uasset> summary            # exports, imports counts, functions
  kismet.py <asset.uasset> funcs              # function names with bytecode size
  kismet.py <asset.uasset> dis [Func ...]     # pseudo-code of the given functions (all if none)
  kismet.py <asset.uasset> calls [Func ...]   # functions each function calls
"""
import struct, sys, os

class R:
    def __init__(self, data, pos=0):
        self.d = data; self.p = pos
    def u8(self): v = self.d[self.p]; self.p += 1; return v
    def u16(self): v = struct.unpack_from('<H', self.d, self.p)[0]; self.p += 2; return v
    def i32(self): v = struct.unpack_from('<i', self.d, self.p)[0]; self.p += 4; return v
    def u32(self): v = struct.unpack_from('<I', self.d, self.p)[0]; self.p += 4; return v
    def i64(self): v = struct.unpack_from('<q', self.d, self.p)[0]; self.p += 8; return v
    def f32(self): v = struct.unpack_from('<f', self.d, self.p)[0]; self.p += 4; return v
    def raw(self, n): v = self.d[self.p:self.p + n]; self.p += n; return v
    def fstr(self):
        n = self.i32()
        if n == 0: return ''
        if n < 0: return self.raw(-n * 2).decode('utf-16-le', 'replace').rstrip('\x00')
        return self.raw(n).decode('latin-1').rstrip('\x00')

class Package:
    def __init__(self, uasset):
        self.path = uasset
        h = open(uasset, 'rb').read()
        uexp = uasset[:-7] + '.uexp'
        self.data = h + (open(uexp, 'rb').read() if os.path.exists(uexp) else b'')
        r = R(h)
        assert r.u32() == 0x9E2A83C1, 'bad magic'
        legacy = r.i32(); r.i32()  # legacy UE3 version
        self.ue4ver = r.i32(); r.i32()
        n = r.i32(); r.raw(n * 20)  # custom versions (guid + int)
        self.header_size = r.i32()
        r.fstr(); r.u32()
        name_count, name_off = r.i32(), r.i32()
        r.i32(); r.i32()  # gatherable text
        exp_count, exp_off = r.i32(), r.i32()
        imp_count, imp_off = r.i32(), r.i32()
        # names
        q = R(h, name_off); self.names = []
        for _ in range(name_count):
            s = q.fstr(); q.u16(); q.u16(); self.names.append(s)
        # imports
        q = R(h, imp_off); self.imports = []
        for _ in range(imp_count):
            cp = self.fname(q); cn = self.fname(q); outer = q.i32(); on = self.fname(q)
            self.imports.append(dict(class_package=cp, class_name=cn, outer=outer, name=on))
        # exports
        q = R(h, exp_off); self.exports = []
        for _ in range(exp_count):
            e = dict(cls=q.i32(), sup=q.i32(), tmpl=q.i32(), outer=q.i32(), name=self.fname(q), flags=q.u32(),
                     size=q.i64(), off=q.i64())
            q.raw(4 * 3 + 16 + 4 + 4 * 2 + 4 * 5)
            self.exports.append(e)

    def fname(self, r):
        i = r.i32(); num = r.i32()
        s = self.names[i] if 0 <= i < len(self.names) else '?name%d' % i
        return s if num == 0 else '%s_%d' % (s, num - 1)

    def ref(self, idx):
        if idx == 0: return 'None'
        if idx < 0:
            imp = self.imports[-idx - 1]
            outer = self.ref(imp['outer']) if imp['outer'] else ''
            short = outer.split('.')[-1].split('/')[-1] if outer else ''
            return (short + '.' if short and imp['class_name'] in ('Function',) else '') + imp['name']
        exp = self.exports[idx - 1]
        return exp['name']

    def class_of(self, e):
        return self.ref(e['cls'])

    def functions(self):
        out = []
        for i, e in enumerate(self.exports):
            if self.class_of(e) == 'Function':
                code = self.bytecode(e)
                out.append((e['name'], code))
        return out

    def bytecode(self, e):
        # Cooked 4.23 layout varies before the script; find it from the end instead:
        # [... | int32 BytecodeSize | int32 StorageSize | script ... EX_EndOfScript | FunctionFlags | EventGraphFunction | EventGraphCallOffset (+ RepOffset)]
        # Several (size, end) pairs can match by chance, so keep the one that disassembles cleanly.
        s, n, d = e['off'], e['size'], self.data
        cands = []
        for tail in (12, 14, 16, 18, 20):
            end = s + n - tail
            if end <= s or d[end - 1] != 0x53: continue
            for k in range(end - 8, s - 1, -1):
                S = struct.unpack_from('<i', d, k + 4)[0]
                if S > 0 and k + 8 + S == end:
                    cands.append(d[k + 8:end])
        for c in cands:
            try:
                dd = Dis(self, c)
                lines = dd.run()
                if not any('!!' in l for l in lines):
                    return c
            except Exception:
                pass
        return cands[0] if cands else None

# ---------------- Kismet disassembler (UE 4.23) ----------------
OP = {0x00:'LocalVariable',0x01:'InstanceVariable',0x02:'DefaultVariable',0x04:'Return',0x06:'Jump',0x07:'JumpIfNot',
      0x09:'Assert',0x0B:'Nothing',0x0F:'Let',0x12:'ClassContext',0x13:'MetaCast',0x14:'LetBool',0x15:'EndParmValue',
      0x16:'EndFunctionParms',0x17:'Self',0x18:'Skip',0x19:'Context',0x1A:'Context_FailSilent',0x1B:'VirtualFunction',
      0x1C:'FinalFunction',0x1D:'IntConst',0x1E:'FloatConst',0x1F:'StringConst',0x20:'ObjectConst',0x21:'NameConst',
      0x22:'RotationConst',0x23:'VectorConst',0x24:'ByteConst',0x25:'IntZero',0x26:'IntOne',0x27:'True',0x28:'False',
      0x29:'TextConst',0x2A:'NoObject',0x2B:'TransformConst',0x2C:'IntConstByte',0x2D:'NoInterface',0x2E:'DynamicCast',
      0x2F:'StructConst',0x30:'EndStructConst',0x31:'SetArray',0x32:'EndArray',0x34:'UnicodeStringConst',0x35:'Int64Const',
      0x36:'UInt64Const',0x38:'PrimitiveCast',0x39:'SetSet',0x3A:'EndSet',0x3B:'SetMap',0x3C:'EndMap',0x3D:'SetConst',
      0x3E:'EndSetConst',0x3F:'MapConst',0x40:'EndMapConst',0x42:'StructMemberContext',0x43:'LetMulticastDelegate',
      0x44:'LetDelegate',0x45:'LocalVirtualFunction',0x46:'LocalFinalFunction',0x48:'LocalOutVariable',0x4A:'DeprecatedOp4A',
      0x4B:'InstanceDelegate',0x4C:'PushExecutionFlow',0x4D:'PopExecutionFlow',0x4E:'ComputedJump',0x4F:'PopExecutionFlowIfNot',
      0x50:'Breakpoint',0x51:'InterfaceContext',0x52:'ObjToInterfaceCast',0x53:'EndOfScript',0x54:'CrossInterfaceCast',
      0x55:'InterfaceToObjCast',0x5A:'WireTracepoint',0x5B:'SkipOffsetConst',0x5C:'AddMulticastDelegate',
      0x5D:'ClearMulticastDelegate',0x5E:'Tracepoint',0x5F:'LetObj',0x60:'LetWeakObjPtr',0x61:'BindDelegate',
      0x62:'RemoveMulticastDelegate',0x63:'CallMulticastDelegate',0x64:'LetValueOnPersistentFrame',0x65:'ArrayConst',
      0x66:'EndArrayConst',0x67:'SoftObjectConst',0x68:'CallMath',0x69:'SwitchValue',0x6A:'InstrumentationEvent',
      0x6B:'ArrayGetByRef'}

class Dis:
    def __init__(self, pkg, code):
        self.pkg = pkg; self.r = R(code); self.code = code
        self.calls = []

    def obj(self): return self.pkg.ref(self.r.i32())
    def name(self): return self.pkg.fname(self.r)

    def args(self, end=0x16):
        out = []
        while self.r.d[self.r.p] != end:
            out.append(self.expr())
        self.r.p += 1
        return out

    def expr(self):
        r = self.r
        op = r.u8()
        n = OP.get(op)
        if n is None:
            raise RuntimeError('unknown opcode 0x%02x at %d' % (op, r.p - 1))
        if op in (0x00, 0x01, 0x02, 0x48): return self.obj()
        if op == 0x04: return 'return ' + self.expr()
        if op == 0x06: return 'goto %d' % r.u32()
        if op == 0x07:
            t = r.u32(); return 'if not (%s) goto %d' % (self.expr(), t)
        if op == 0x09:
            r.u16(); r.u8(); return 'assert(%s)' % self.expr()
        if op in (0x0B, 0x15, 0x4D, 0x50, 0x53, 0x5A, 0x5E, 0x4A): return n
        if op == 0x0F:
            self.obj(); a = self.expr(); b = self.expr(); return '%s = %s' % (a, b)
        if op in (0x14, 0x5F, 0x60, 0x43, 0x44):
            a = self.expr(); b = self.expr(); return '%s = %s' % (a, b)
        if op in (0x12, 0x19, 0x1A):
            o = self.expr(); r.u32(); self.obj(); c = self.expr()
            return '%s.%s' % (o, c)
        if op in (0x13, 0x2E, 0x52, 0x54, 0x55):
            c = self.obj(); return 'Cast<%s>(%s)' % (c, self.expr())
        if op == 0x16: return ')'
        if op == 0x17: return 'self'
        if op == 0x18:
            r.u32(); return self.expr()
        if op in (0x1B, 0x45):
            f = self.name(); a = self.args(); self.calls.append(f); return '%s(%s)' % (f, ', '.join(a))
        if op in (0x1C, 0x46, 0x68, 0x63):
            f = self.obj(); a = self.args(); self.calls.append(f); return '%s(%s)' % (f, ', '.join(a))
        if op == 0x1D: return str(r.i32())
        if op == 0x1E: return '%g' % r.f32()
        if op == 0x1F:
            s = bytearray()
            while True:
                c = r.u8()
                if c == 0: break
                s.append(c)
            return repr(s.decode('latin-1'))
        if op == 0x34:
            s = bytearray()
            while True:
                c = r.raw(2)
                if c == b'\x00\x00': break
                s += c
            return repr(s.decode('utf-16-le', 'replace'))
        if op == 0x20: return self.obj()
        if op == 0x21: return "'%s'" % self.name()
        if op in (0x22, 0x23): return '(%g,%g,%g)' % (r.f32(), r.f32(), r.f32())
        if op == 0x2B: return 'Transform(' + ','.join('%g' % r.f32() for _ in range(10)) + ')'
        if op in (0x24, 0x2C): return str(r.u8())
        if op == 0x25: return '0'
        if op == 0x26: return '1'
        if op == 0x27: return 'true'
        if op == 0x28: return 'false'
        if op in (0x2A, 0x2D): return 'nullptr'
        if op == 0x29:
            t = r.u8()
            if t == 0: return 'Text()'
            if t == 1: a = self.expr(); b = self.expr(); c = self.expr(); return 'Text(%s)' % a
            if t in (2, 3): return 'Text(%s)' % self.expr()
            if t == 4: self.obj(); a = self.expr(); b = self.expr(); return 'Text(table %s %s)' % (a, b)
            return 'Text(?)'
        if op == 0x2F:
            s = self.obj(); r.i32(); a = self.args(0x30); return '%s{%s}' % (s, ', '.join(a))
        if op == 0x31:
            t = self.expr(); a = self.args(0x32); return '%s = [%s]' % (t, ', '.join(a))
        if op in (0x35, 0x36): return str(r.i64())
        if op == 0x38:
            r.u8(); return 'cast(%s)' % self.expr()
        if op == 0x39:
            t = self.expr(); r.i32(); a = self.args(0x3A); return '%s = set(%s)' % (t, ', '.join(a))
        if op == 0x3B:
            t = self.expr(); r.i32(); a = self.args(0x3C); return '%s = map(%s)' % (t, ', '.join(a))
        if op == 0x3D:
            self.obj(); r.i32(); a = self.args(0x3E); return 'set(%s)' % ', '.join(a)
        if op == 0x3F:
            self.obj(); self.obj(); r.i32(); a = self.args(0x40); return 'map(%s)' % ', '.join(a)
        if op == 0x42:
            p = self.obj(); return '%s.%s' % (self.expr(), p)
        if op == 0x4B: return 'delegate(%s)' % self.name()
        if op == 0x4C: return 'push_flow %d' % r.u32()
        if op == 0x4E: return 'goto computed(%s)' % self.expr()
        if op == 0x4F: return 'if not (%s) pop_flow' % self.expr()
        if op == 0x51: return self.expr()
        if op == 0x5B: return 'skipoffset %d' % r.u32()
        if op in (0x5C, 0x62):
            a = self.expr(); b = self.expr(); return '%s %s= %s' % (a, '+' if op == 0x5C else '-', b)
        if op == 0x5D: return '%s.Clear()' % self.expr()
        if op == 0x61:
            f = self.name(); a = self.expr(); b = self.expr(); return 'bind %s(%s, %s)' % (f, a, b)
        if op == 0x64:
            p = self.obj(); return '%s = %s' % (p, self.expr())
        if op == 0x65:
            self.obj(); r.i32(); a = self.args(0x66); return '[%s]' % ', '.join(a)
        if op == 0x67: return 'soft(%s)' % self.expr()
        if op == 0x69:
            nc = r.u16(); r.u32(); idx = self.expr(); cases = []
            for _ in range(nc):
                k = self.expr(); r.u32(); v = self.expr(); cases.append('%s:%s' % (k, v))
            d = self.expr(); return 'switch(%s){%s; default:%s}' % (idx, ', '.join(cases), d)
        if op == 0x6A:
            t = r.u8()
            if t == 4: self.name()
            return 'instrumentation'
        if op == 0x6B:
            a = self.expr(); b = self.expr(); return '%s[%s]' % (a, b)
        raise RuntimeError('unhandled opcode %s' % n)

    def run(self):
        lines = []
        while self.r.p < len(self.code):
            pos = self.r.p
            try:
                s = self.expr()
            except Exception as ex:
                lines.append('  !! %s' % ex); break
            if s in ('EndOfScript',): break
            if s not in ('Nothing', 'WireTracepoint', 'Tracepoint'):
                lines.append('  %5d  %s' % (pos, s))
        return lines

if __name__ == '__main__':
    pkg = Package(sys.argv[1]); cmd = sys.argv[2] if len(sys.argv) > 2 else 'summary'
    want = set(sys.argv[3:])
    funcs = pkg.functions()
    if cmd == 'summary':
        print('UE4 version', pkg.ue4ver, 'names', len(pkg.names), 'imports', len(pkg.imports), 'exports', len(pkg.exports), 'functions', len(funcs))
    elif cmd == 'funcs':
        for n, c in funcs: print(len(c) if c else -1, n)
    else:
        for n, c in funcs:
            if want and n not in want: continue
            if not c: continue
            d = Dis(pkg, c); lines = d.run()
            if cmd == 'dis':
                print('function %s:' % n); print('\n'.join(lines)); print()
            elif cmd == 'calls':
                print('%s: %s' % (n, ', '.join(sorted(set(d.calls)))))
