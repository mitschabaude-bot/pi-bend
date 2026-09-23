#!/usr/bin/env python3
"""Run pinned named assertions and real temporary-tree loader comparisons."""
import argparse
import json
import os
import pathlib
import subprocess
import tempfile

parser = argparse.ArgumentParser()
parser.add_argument('--upstream', default='../pi-mono')
parser.add_argument('command', nargs=argparse.REMAINDER)
args = parser.parse_args()
command = args.command[1:] if args.command[:1] == ['--'] else args.command
root = pathlib.Path(__file__).resolve().parent.parent
upstream = pathlib.Path(args.upstream).resolve() / 'packages/coding-agent'


def run(inputs):
    results = []
    for start in range(0, len(inputs), 8):
        batch = inputs[start:start + 8]
        process = subprocess.run(command + [json.dumps(value) for value in batch], cwd=root,
                                 check=True, capture_output=True, text=True, timeout=120)
        lines = process.stdout.splitlines()
        assert len(lines) == len(batch), (process.stdout, process.stderr)
        results.extend(map(json.loads, lines))
    return results


def normalize(value):
    # The two parsers retain their own source spans and exception wording.
    for issue in value['diagnostics']:
        if 'at line ' in issue['message']:
            issue['message'] = 'YAML parse error'
    return value


with tempfile.TemporaryDirectory(prefix='pi-skills-') as temporary:
    base = pathlib.Path(temporary)
    home, cwd, agent = [base / name for name in ('home', 'project', 'agent')]
    for directory in (home, cwd, agent):
        directory.mkdir()

    def write(path, content):
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content)
        return path

    def skill(path, name, description='Useful skill', extra=''):
        return write(path, f'---\nname: {name}\ndescription: {json.dumps(description, ensure_ascii=False)}\n{extra}---\nInstructions\n')

    def directory(path):
        return {'mode': 'dir', 'dir': str(path), 'source': 'test'}

    def load(paths=(), defaults=True):
        return {'mode': 'load', 'cwd': str(cwd), 'agentDir': str(agent),
                'skillPaths': list(map(str, paths)), 'includeDefaults': defaults,
                'home': str(home), 'environmentCwd': str(root)}

    user = skill(agent / 'skills/alpha/SKILL.md', 'shared')
    project = skill(cwd / '.pi/skills/alpha/SKILL.md', 'shared', 'Losing project')
    skill(cwd / '.pi/skills/beta/SKILL.md', 'project-only')
    extra = skill(base / 'extra/SKILL.md', 'shared', 'Losing explicit')
    lone = skill(home / 'lone.md', 'lone')
    linked = base / 'linked.md'
    linked.symlink_to(lone)
    write(base / 'ordinary.txt', 'not a skill')
    os.mkfifo(base / 'pipe.md')
    cases = [load(), load([extra, lone, linked, lone]), load([project, user], False),
             load([user, project, extra], False), load([lone.as_uri(), ' ~/lone.md '], False),
             load(['../home/lone.md'], False), load([base / 'missing', base / 'ordinary.txt', base / 'pipe.md']),
             directory(base / 'absent')]

    tree = base / 'tree'
    skill(tree / 'z.md', 'root-file')
    skill(tree / 'a/SKILL.md', 'nested')
    skill(tree / 'a/child/SKILL.md', 'hidden-by-root')
    skill(tree / 'a/other.md', 'hidden-sibling')
    skill(tree / 'b/other.md', 'nested-doc-not-skill')
    skill(tree / 'b/deep/SKILL.md', 'deep')
    skill(tree / '.hidden/SKILL.md', 'hidden')
    skill(tree / 'node_modules/pkg/SKILL.md', 'module')
    (tree / 'file-link.md').symlink_to(lone)
    (tree / 'dir-link').symlink_to(base / 'extra', target_is_directory=True)
    (tree / 'broken').symlink_to(base / 'does-not-exist')
    os.mkfifo(tree / 'fifo.md')
    cases += [directory(tree)]
    preferred = base / 'preferred'
    skill(preferred / 'SKILL.md', 'root-wins')
    skill(preferred / 'z/SKILL.md', 'not-reached')
    cases += [directory(preferred)]
    invalid_root = base / 'invalid-root'
    write(invalid_root / 'SKILL.md', '---\nname: root\n---\n')
    skill(invalid_root / 'child/SKILL.md', 'not-reached')
    cases += [directory(invalid_root)]

    ignored = base / 'ignored'
    for name in ('a', 'b', 'c', 'd', 'nested/one', 'nested/two'):
        skill(ignored / name / 'SKILL.md', name.replace('/', '-'))
    write(ignored / '.gitignore', 'a/\nb/\nc/\n')
    write(ignored / '.ignore', '!b/\n!c/\n')
    write(ignored / '.fdignore', 'c/\n')
    write(ignored / 'nested/.gitignore', 'one/\n')
    cases += [directory(ignored)]
    ignored_root = base / 'ignored-root'
    skill(ignored_root / 'SKILL.md', 'ignored-root')
    skill(ignored_root / 'child/SKILL.md', 'visible-child')
    write(ignored_root / '.gitignore', '/SKILL.md\n')
    cases += [directory(ignored_root)]
    metadata = base / 'metadata'
    skill(metadata / 'normal/SKILL.md', 'normal', 'x' * 1024)
    skill(metadata / 'long/SKILL.md', 'long', 'x' * 1025)
    write(metadata / 'yaml/SKILL.md', '\ufeff---\r\nname: yaml\r\ndescription: >\r\n  multi\r\n  line\r\nunknown:\r\n- first\r\n- nested: true\r\n---\r\nBody')
    cases += [directory(metadata)]

    extras = base / 'cases.json'
    extras.write_text(json.dumps(cases))
    reference = json.loads(subprocess.check_output(
        ['bun', 'tests/skills_reference.ts', str(upstream), str(home), str(extras)], cwd=root, text=True))
    results = run([record['input'] for record in reference['records']])
    for record, actual in zip(reference['records'], results):
        assert normalize(actual) == normalize(record['expected']), (record['name'], record['input'], actual, record['expected'])

    # Native strictness and deliberate corrections, never sent to the upstream
    # oracle when it can hang, throw a JS type error, or embodies the known bug.
    adaptations = []
    escaped = base / 'escaped'
    skill(escaped / '!literal/SKILL.md', 'literal')
    skill(escaped / 'kept/SKILL.md', 'kept')
    write(escaped / '.gitignore', '\\!literal/\n')
    adaptations.append((directory(escaped), ['kept'], []))
    cycle = base / 'cycle'
    skill(cycle / 'good/SKILL.md', 'good')
    (cycle / 'loop').symlink_to(cycle, target_is_directory=True)
    adaptations.append((directory(cycle), ['good'], ['Recursive skill directory symlink']))
    for key, value in [('name', '123'), ('description', '[one]'), ('disable-model-invocation', '"yes"')]:
        target = base / ('wrong-' + key)
        fields = {'name': 'valid', 'description': 'Useful', 'disable-model-invocation': 'false'}
        fields[key] = value
        write(target / 'SKILL.md', '---\n' + ''.join(f'{k}: {v}\n' for k, v in fields.items()) + '---\n')
        expected = 'a boolean' if key == 'disable-model-invocation' else 'a string'
        adaptations.append((directory(target), [], [f'frontmatter {key} must be {expected}']))
    malformed = base / 'malformed'
    write(malformed / 'SKILL.md', '').write_bytes(b'---\ndescription: \xff\n---\n')
    adaptations.append((directory(malformed), [], ['Invalid UTF-8 in skill file']))
    unicode = base / 'unicode'
    skill(unicode / 'SKILL.md', 'unicode', '\U0001f600' * 1024)
    adaptations.append((directory(unicode), ['unicode'], []))
    for (request, names, messages), actual in zip(adaptations, run([case[0] for case in adaptations])):
        assert [skill['name'] for skill in actual['skills']] == names, (request, actual)
        assert [issue['message'] for issue in actual['diagnostics']] == messages, (request, actual)
    print(f"{len(reference['names'])} pinned named assertions; {len(results)} full loader comparisons; {len(adaptations)} native policy cases passed")
