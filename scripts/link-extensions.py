#!/usr/bin/env python3
"""Generate a Bend CLI entry point with explicitly linked native extensions."""

import hashlib
import re
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
MAIN = ROOT / "packages/coding-agent/src/main.bend"
REGISTRY = ROOT / "packages/coding-agent/src/extensions/index.bend"
IMPORT = re.compile(r"^import (\.\.?/\S+) as (\w+)$", re.MULTILINE)


def bend_path(path: Path) -> str:
    value = str(path)
    if re.search(r"[\s\"\\]", value):
        raise SystemExit(f"Bend import path contains unsupported characters: {value}")
    return value


def main() -> None:
    if len(sys.argv) < 2:
        raise SystemExit("usage: link-extensions.py EXTENSION.bend ...")
    requested = [(Path(arg).resolve(strict=True), arg) for arg in sys.argv[1:]]
    for path, raw in requested:
        if not path.is_file() or path.suffix != ".bend":
            raise SystemExit(f"extension must be a .bend file: {path}")
        bend_path(path)
        bend_path(Path(raw))
    requested = list(dict((path, (path, raw)) for path, raw in requested).values())
    paths = [path for path, _ in requested]
    key = hashlib.sha256("\0".join(map(str, paths)).encode()).hexdigest()[:16]
    linked = REGISTRY.parent / f".linked-{key}.bend"
    entry = MAIN.parent / f".main-linked-{key}.bend"

    lines = [
        "import Base",
        "import ../core/extensions/types.bend as T",
        "import ./index.bend as Standard",
    ]
    lines.extend(f"import {bend_path(path)} as Extension{i}" for i, path in enumerate(paths))
    lines.extend(
        [
            "",
            "def builtInExtensions() -> List<&1, T.InlineExtension>: Standard.builtInExtensions()",
            "",
            "def linkedExtensions(names: List<&2, String>) -> List<&1, T.InlineExtension>:",
            "  match names:",
            "    case Nil{}: Nil{}",
            "    case name <> rest:",
            "      match name:",
        ]
    )
    for i, (path, raw) in enumerate(requested):
        name = bend_path(path)
        for alias in dict.fromkeys((name, raw)):
            lines.append(
                f'        case "{alias}": '
                f'T.InlineExtension{{"{name}", api => Extension{i}.extension(api), False{{}}}} <> linkedExtensions(rest)'
            )
    lines.append("        case _: linkedExtensions(rest)")
    lines.extend(
        [
            "",
            "def selected(+names: List<&2, String>) -> List<&1, T.InlineExtension>:",
            "  List.append(&1, T.InlineExtension, linkedExtensions(names), Standard.selected(names))",
            "",
            "def withoutLinked(names: List<&2, String>) -> List<&2, String>:",
            "  match names:",
            "    case Nil{}: Nil{}",
            "    case +name <> +rest:",
        ]
    )
    aliases = dict.fromkeys(alias for path, raw in requested for alias in (bend_path(path), raw))
    known = " || ".join(f'String.eq(name, "{alias}")' for alias in aliases)
    lines.append(f"      Bool.pick(List<&2, String>, {known}, withoutLinked(rest), name <> withoutLinked(rest))")
    lines.extend(["", "def unlinked(names: List<&2, String>) -> List<&2, T.LoadError>:", "  Standard.unlinked(withoutLinked(names))"])
    linked.write_text("\n".join(lines) + "\n")

    def linked_import(match: re.Match[str]) -> str:
        source, alias = match.groups()
        if alias == "LinkedExtensions":
            return f"import ./extensions/{linked.name} as LinkedExtensions"
        return match.group(0)

    entry.write_text(IMPORT.sub(linked_import, MAIN.read_text()))
    print(entry.relative_to(ROOT), linked.relative_to(ROOT))


if __name__ == "__main__":
    main()
