"""Sorted range lookups as Bend decision trees of plain definitions.

A definition that matches a Bool parameter compiles to a direct branch. The
earlier `Bool.pick(Unit -> T, c, _ => a, _ => b)(Unit{})` form allocated,
applied and dropped two closures per tree level on every lookup.
"""

def decision_tree(name, rows, key, leaf, result, params):
    """Definitions for a binary search over `rows`, sorted (lower bound, value)
    pairs, comparing the U32 parameter `key`; `params` are (binder, type)
    pairs passed down to the leaves. Returns (definitions, root expression)."""
    definitions = []
    arguments = ",".join(binder for binder, _ in params)
    signature = ",".join(f"+{binder}: {kind}" for binder, kind in params)

    def node(rows):
        if len(rows) == 1:
            return leaf(rows[0][1])
        middle = len(rows) // 2
        below, above = node(rows[:middle]), node(rows[middle:])
        index = len(definitions)
        definitions.append(f"def {name}{index}({signature},below: Bool) -> {result}:\n  match below:\n    case True{{}}: {below}\n    case False{{}}: {above}\n")
        return f"{name}{index}({arguments},U32.is_lt({key},{rows[middle][0]}))"

    root = node(rows)
    return "".join(definitions), root
