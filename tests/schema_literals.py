"""Test-only encoding of JSON fixture values as native Bend expressions."""
import json
import struct

def seq(items):
    return ' <> '.join([*items, 'Nil{}'])


def floating(v):
    hi, lo = struct.unpack('>II', struct.pack('>d', v))
    return f'F.fromBits({hi}, {lo})'


def value(v):
    if v is None:
        return 'V.Null{}'
    if isinstance(v, bool):
        return f'V.Boolean{{{"True{}" if v else "False{}"}}}'
    if isinstance(v, (int, float)):
        return 'V.Number{' + floating(v) + '}'
    if isinstance(v, str):
        return 'V.Text{' + json.dumps(v) + '}'
    if isinstance(v, list):
        return 'V.ArrayValue{' + seq(map(value, v)) + '}'
    return 'V.ObjectValue{R.Record{' + seq('R.Property{' + json.dumps(k) + ', ' + value(x) + '}' for k, x in v.items()) + '}}'


