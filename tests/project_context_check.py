#!/usr/bin/env python3
from upstream_pin import UPSTREAM
import argparse, json, pathlib, subprocess, tempfile, os

p = argparse.ArgumentParser()
p.add_argument("--upstream", default=str(UPSTREAM))
p.add_argument("command", nargs=argparse.REMAINDER)
a = p.parse_args()
command = a.command[1:] if a.command[:1] == ["--"] else a.command
root = pathlib.Path(__file__).resolve().parent.parent
with tempfile.TemporaryDirectory(prefix="pi-context-") as temporary:
    base = pathlib.Path(temporary)
    inputs = []

    def write(path, text):
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text)
        return path

    def scenario(name):
        directory = base / name
        directory.mkdir()
        return directory

    def context(cwd, agent, name="supplemental"):
        value = {
            "cwd": str(cwd),
            "agentDir": str(agent),
            "name": name,
            "environmentCwd": str(root),
            "home": str(base),
        }
        inputs.append(value)
        return value

    def git(cwd):
        inputs.append({"mode": "git", "cwd": str(cwd)})

    agent = scenario("agent")
    project = scenario("project")
    leaf = project / "a/b"
    leaf.mkdir(parents=True)
    write(agent / "AGENTS.md", "global")
    write(agent / "AGENTS.override.md", "global override")
    write(project / "AGENTS.md", "project")
    write(leaf / "AGENTS.md", "service")
    write(leaf / "AGENTS.override.md", "service override")
    context(
        leaf,
        agent,
        "should prefer AGENTS.override.md within each directory while preserving ancestor layering",
    )
    context(leaf, project, "global directory also in ancestor chain is included once")
    fallback = scenario("fallback")
    (fallback / "AGENTS.override.md").mkdir()
    (fallback / "AGENTS.md").mkdir()
    write(fallback / "CLAUDE.md", "Fallback instructions")
    context(
        fallback, agent, "should ignore context file candidates that are directories"
    )
    for filename in (
        "AGENTS.override.md",
        "AGENTS.md",
        "AGENTS.MD",
        "CLAUDE.md",
        "CLAUDE.MD",
    ):
        directory = scenario("candidate-" + filename)
        write(directory / filename, "\ufeffcontent\r\n\ufeffinterior BOM retained")
        context(directory, agent)
    empty = scenario("empty")
    write(empty / "AGENTS.override.md", "")
    write(empty / "AGENTS.md", "not selected")
    context(empty, agent)
    linked = scenario("linked")
    (linked / "AGENTS.md").symlink_to(project / "AGENTS.md")
    context(linked, agent)
    broken = scenario("broken")
    (broken / "AGENTS.md").symlink_to(base / "missing")
    write(broken / "CLAUDE.md", "fallback")
    context(broken, agent)
    fifo = scenario("fifo")
    os.mkfifo(fifo / "AGENTS.override.md")
    write(fifo / "AGENTS.md", "regular")
    context(fifo, agent)
    large = scenario("large")
    write(large / "AGENTS.md", "Project guidance.\n" * 10000)
    context(large, agent)
    deep = scenario("deep")
    write(deep / "AGENTS.md", "above 64 levels")
    deep_leaf = deep.joinpath(*["d"] * 70)
    deep_leaf.mkdir(parents=True)
    write(deep_leaf / "AGENTS.md", "leaf")
    context(deep_leaf, agent)
    ordinary = scenario("ordinary")
    write(ordinary / ".git/HEAD", "ref: refs/heads/main\n")
    child = ordinary / "src"
    child.mkdir()
    git(child)
    nohead = scenario("nohead")
    (nohead / ".git").mkdir()
    git(nohead)
    for label, marker, head, common in [
        ("relative", "gitdir: metadata", True, None),
        ("absolute", "gitdir: TARGET", True, "../shared"),
        ("malformed", "not a git marker", True, None),
        ("missing-head", "gitdir: metadata", False, None),
    ]:
        directory = scenario(label)
        metadata = directory / "metadata"
        metadata.mkdir()
        write(directory / ".git", marker.replace("TARGET", str(metadata)))
        if head:
            write(metadata / "HEAD", "ref: refs/heads/main")
        if common:
            write(metadata / "commondir", common + "\n")
        git(directory)
    nested = ordinary / "nested"
    nested.mkdir()
    write(nested / ".git", "unrelated file")
    git(nested)
    # Canonical shadow matching must survive a symlinked cwd spelling.
    main = scenario("shadow")
    worktree = main / "worktrees/feat"
    src = worktree / "src"
    src.mkdir(parents=True)
    gitdir = main / ".git/worktrees/feat"
    write(main / ".git/HEAD", "main")
    write(gitdir / "HEAD", "feat")
    write(gitdir / "commondir", "../..")
    write(worktree / ".git", "gitdir: " + str(gitdir))
    write(main / "AGENTS.md", "shadowed")
    write(worktree / "AGENTS.md", "worktree")
    alias = base / "shadow-alias"
    alias.symlink_to(main, target_is_directory=True)
    context(alias / "worktrees/feat/src", agent)
    git(src)
    input_file = base / "inputs.json"
    input_file.write_text(json.dumps(inputs))
    reference = json.loads(
        subprocess.check_output(
            [
                "bun",
                "tests/project_context_reference.ts",
                str(pathlib.Path(a.upstream).resolve()),
                str(base),
                str(input_file),
            ],
            cwd=root,
            text=True,
        )
    )

    def run(requests):
        output = []
        for i in range(0, len(requests), 6):
            result = subprocess.run(
                command + [json.dumps(v) for v in requests[i : i + 6]],
                cwd=root,
                text=True,
                capture_output=True,
                check=True,
                timeout=120,
            )
            output.extend(map(json.loads, result.stdout.splitlines()))
        assert len(output) == len(requests)
        return output

    for case, actual in zip(
        reference["records"], run([r["input"] for r in reference["records"]])
    ):
        assert actual == case["expected"], (
            case["name"],
            case["input"],
            actual,
            case["expected"],
        )
    # Recoverable malformed input uses explicit warning data, then tries fallback.
    invalid = scenario("invalid")
    write(invalid / "AGENTS.md", "").write_bytes(b"\xff")
    write(invalid / "CLAUDE.md", "valid fallback")
    value = run(
        [
            {
                "cwd": str(invalid),
                "agentDir": str(base / "absent"),
                "environmentCwd": str(root),
                "home": str(base),
            }
        ]
    )[0]
    assert value == {
        "files": [{"path": str(invalid / "CLAUDE.md"), "content": "valid fallback"}],
        "diagnostics": [
            {
                "message": "Invalid UTF-8 in context file",
                "path": str(invalid / "AGENTS.md"),
            }
        ],
    }, value
    print(
        f"{len(reference['names'])} original nested-worktree tests; {len(reference['records'])} complete context/Git comparisons; strict UTF-8 fallback passed"
    )
