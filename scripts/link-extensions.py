#!/usr/bin/env python3
"""Generate a Bend CLI entry point with explicitly linked native extensions."""

import hashlib
import json
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
    configured = []
    arguments = sys.argv[1:]
    if arguments[:1] == ["--sources-json"]:
        configured = json.load(sys.stdin)
        if not isinstance(configured, list) or any(not isinstance(path, str) for path in configured):
            raise SystemExit("configured extensions must be a JSON array of paths")
        arguments = arguments[1:]
    paths = list(dict.fromkeys(Path(arg).resolve(strict=True) for arg in [*configured, *arguments]))
    if not paths:
        return
    for path in paths:
        if not path.is_file() or path.suffix != ".bend":
            raise SystemExit(f"extension must be a .bend file: {path}")
        bend_path(path)
    key = hashlib.sha256("\0".join(map(str, paths)).encode()).hexdigest()[:16]
    linked = REGISTRY.parent / f".linked-{key}.bend"
    entry = MAIN.parent / f".main-linked-{key}.bend"

    lines = [
        "import Base",
        "import ../core/extensions/types.bend as T",
        "import ../../../runtime/src/callback.bend as C",
        "import ./index.bend as Standard",
    ]
    lines.extend(f"import {bend_path(path)} as Extension{i}" for i, path in enumerate(paths))
    lines.extend(
        [
            "",
            "def builtInExtensions() -> IO(List<&2, T.InlineExtension>): Standard.builtInExtensions()",
            "",
            "def linkedExtensions(names: List<&2, String>) -> IO(List<&2, T.InlineExtension>):",
            "  match names:",
            "    case Nil{}: IO.pure(List<&2, T.InlineExtension>, Nil{})",
            "    case name <> rest:",
            "      match name:",
        ]
    )
    for i, path in enumerate(paths):
        name = bend_path(path)
        lines.append(
            f'        case "{name}":'
        )
        lines.extend([
            "          do IO<List<&2, T.InlineExtension>>:",
            f"            factory : T.ExtensionFactory() <- C.create(~Unit, ~T.ExtensionAPI, ~Result<&2, &2, String, Unit>, ~(_ => api => Extension{i}.extension(api)), Unit{{}})",
            "            others : List<&2, T.InlineExtension> <- linkedExtensions(rest)",
            f'            return T.InlineExtension{{"{name}", factory, False{{}}}} <> others',
        ])
    lines.append("        case _: linkedExtensions(rest)")
    lines.extend(
        [
            "",
            "def selected(+names: List<&2, String>) -> IO(List<&2, T.InlineExtension>):",
            "  do IO<List<&2, T.InlineExtension>>:",
            "    linked : List<&2, T.InlineExtension> <- linkedExtensions(names)",
            "    standard : List<&2, T.InlineExtension> <- Standard.selected(names)",
            "    return List.append(&2, T.InlineExtension, linked, standard)",
            "",
            "def withoutLinked(names: List<&2, String>) -> List<&2, String>:",
            "  match names:",
            "    case Nil{}: Nil{}",
            "    case +name <> +rest:",
        ]
    )
    known = " || ".join(f'String.eq(name, "{bend_path(path)}")' for path in paths)
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
