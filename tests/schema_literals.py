"""Test-only encoding of JSON fixture values as native Bend expressions."""
import struct

def seq(items):
    return ' <> '.join([*items, 'Nil{}'])


def floating(v):
    hi, lo = struct.unpack('>II', struct.pack('>d', v))
    return f'F.fromBits({hi}, {lo})'


def string(text):
    escapes = {'\n': r'\n', '\r': r'\r', '\t': r'\t', '\0': r'\0', '\\': r'\\', '"': r'\"'}
    parts = []
    for char in text:
        code = ord(char)
        if char in escapes:
            parts.append(escapes[char])
        elif code < 32 or 0xD800 <= code <= 0xDFFF or code in (0x2028, 0x2029):
            parts.append('\\u{' + format(code, 'X') + '}')
        else:
            parts.append(char)
    return '"' + ''.join(parts) + '"'


def value(v):
    if v is None:
        return 'V.Null{}'
    if isinstance(v, bool):
        return f'V.Boolean{{{"True{}" if v else "False{}"}}}'
    if isinstance(v, (int, float)):
        return 'V.Number{' + floating(v) + '}'
    if isinstance(v, str):
        return 'V.Text{' + string(v) + '}'
    if isinstance(v, list):
        return 'V.ArrayValue{' + seq(map(value, v)) + '}'
    return 'V.ObjectValue{R.Record{' + seq('R.Property{' + string(k) + ', ' + value(x) + '}' for k, x in v.items()) + '}}'


