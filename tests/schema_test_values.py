"""Emit Bend expressions for tagged schema fixtures (test-only)."""
def string(points):
    result = 'SNil{}'
    for point in reversed(list(points)): result = f'SCon{{Chr{{{point}}}, {result}}}'
    return result

def valid(v):
    if v[0] in ('null', 'boolean', 'string'): return True
    if v[0] == 'number': return (int(v[1], 16) >> 52) & 2047 != 2047
    if v[0] == 'array': return all(valid(x) for x in v[1])
    if v[0] == 'object': return not v[2] and all(e and valid(x) for k, x, e in v[1])
    return False

def tagged(v):
    import struct
    if v is None: return ['null']
    if isinstance(v, bool): return ['boolean', v]
    if isinstance(v, (float, int)): return ['number', struct.pack('>d', v).hex()]
    if isinstance(v, str): return ['string', list(map(ord, v))]
    if isinstance(v, list): return ['array', [tagged(x) for x in v]]
    return ['object', [[k, tagged(x), True] for k, x in v.items()], []]

def bend(v):
    if not valid(v): raise ValueError('fixture is outside the native JSON data domain')
    kind = v[0]
    if kind == 'null': return 'V.Null{}'
    if kind == 'boolean': return 'V.Boolean{' + ('True{}' if v[1] else 'False{}') + '}'
    if kind == 'number':
        raw=int(v[1],16)
        return f'V.Number{{F.fromBits({raw >> 32}, {raw & 0xffffffff})}}'
    if kind == 'string': return 'V.Text{' + string(v[1]) + '}'
    if kind == 'array': return 'V.ArrayValue{' + ' <> '.join([bend(x) for x in v[1]]+['Nil{}']) + '}'
    record='R.new(V.Value)'
    for key, value, _ in v[1]:
        record=f'R.set(V.Value, {record}, {string(map(ord,key))}, {bend(value)})'
    return f'V.ObjectValue{{{record}}}'
