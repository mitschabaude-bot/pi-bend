"""Emit Bend expressions for tagged schema fixtures (test-only)."""
def string(points):
    result = 'SNil{}'
    for point in reversed(list(points)): result = f'SCon{{Chr{{{point}}}, {result}}}'
    return result

def bend(v):
    kind = v[0]
    if kind == 'undefined': return 'V.Undefined{}'
    if kind == 'null': return 'V.Null{}'
    if kind == 'boolean': return 'V.Boolean{' + ('True{}' if v[1] else 'False{}') + '}'
    if kind == 'number':
        raw=int(v[1],16)
        return f'V.Number{{F.fromBits({raw >> 32}, {raw & 0xffffffff})}}'
    if kind == 'string': return 'V.Text{' + string(v[1]) + '}'
    if kind == 'symbol': return f'V.Symbol{{{v[1]}}}'
    if kind == 'callable': return f'V.Callable{{{v[1]}}}'
    if kind == 'bigint': return 'V.BigInteger{False{}, B.one()}'
    if kind == 'array': return 'V.ArrayValue{' + ' <> '.join([bend(x) for x in v[1]]+['Nil{}']) + '}'
    record='R.new(V.Property<V.Value<U32>>)'
    for key, value, enumerable in v[1]:
        record=f'R.set(V.Property<V.Value<U32>>, {record}, {string(map(ord,key))}, V.Property{{{bend(value)}, '+('True{}' if enumerable else 'False{}')+'})'
    symbols=' <> '.join([f'V.SymbolProperty{{{key}, {bend(value)}}}' for key,value in v[2]]+['Nil{}'])
    return f'V.ObjectValue{{{record}, {symbols}}}'

