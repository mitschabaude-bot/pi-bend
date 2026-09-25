"""PackageManager.resolve for local resources against pinned pi-mono v0.87.1.

Builds fixture trees (user agent directory, project .pi, .agents skill
directories up to the Git root, ignore files, symlinks, settings entries and
exact +/- overrides and minimatch glob patterns) and compares the Bend resolution with the reference
script run under Bun from ../pi-mono/packages/coding-agent.
"""
from upstream_pin import UPSTREAM
import argparse, json, os, subprocess, tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
UPSTREAM = UPSTREAM / 'packages' / 'coding-agent'

def write(path, text=''):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text)

def skill(path, name):
    write(path, '---\nname: %s\ndescription: %s skill\n---\nbody\n' % (name, name))

def fixture(base):
    home, agent = base / 'home', base / 'home' / '.pi' / 'agent'
    outer = base / 'work'; project = outer / 'repo' / 'pkg'
    (outer / 'repo' / '.git').mkdir(parents=True)
    project.mkdir(parents=True)
    for name in ('a', 'b/c'):
        skill(home / '.agents/skills' / name / 'SKILL.md', name.replace('/', '-'))
    write(home / '.agents/skills/root.md'); write(home / '.agents/skills/sub/x.md')
    skill(agent / 'skills/one/SKILL.md', 'one'); write(agent / 'skills/top.md')
    skill(agent / 'skills/nested/deep/SKILL.md', 'deep'); write(agent / 'skills/nested/loose.md')
    skill(agent / 'skills/.hidden/SKILL.md', 'hidden'); skill(agent / 'skills/node_modules/q/SKILL.md', 'q')
    skill(agent / 'skills/ignored/SKILL.md', 'ignored'); write(agent / 'skills/.gitignore', 'ignored/\n# note\n')
    skill(base / 'linked/SKILL.md', 'linked'); os.symlink(base / 'linked', agent / 'skills/link')
    os.symlink(base / 'missing', agent / 'skills/broken')
    write(agent / 'prompts/p1.md'); write(agent / 'prompts/p2.txt'); write(agent / 'prompts/sub/p3.md'); write(agent / 'prompts/.h.md')
    write(agent / 'prompts/skip.md'); write(agent / 'prompts/.ignore', 'skip.md\n')
    write(agent / 'themes/t.json', '{}'); write(agent / 'themes/t.md')
    skill(outer / '.agents/skills/above/SKILL.md', 'above')
    skill(outer / 'repo/.agents/skills/r/SKILL.md', 'r')
    skill(project / '.agents/skills/s/SKILL.md', 's'); write(project / '.agents/skills/s2/extra.md')
    skill(project / '.pi/skills/ps/SKILL.md', 'ps'); write(project / '.pi/prompts/pp.md'); write(project / '.pi/themes/pt.json', '{}')
    skill(base / 'extra/set/e1/SKILL.md', 'e1'); write(base / 'extra/set/e2.md'); skill(home / 'tilde/t1/SKILL.md', 't1')
    write(base / 'extra-prompts/x.md'); write(base / 'extra-prompts/deeper/y.md'); write(base / 'extra-prompts/z.txt')
    skill(agent / 'skills/globbed/SKILL.md', 'globbed'); skill(agent / 'skills/other/SKILL.md', 'other')
    write(base / 'extra-prompts/keep-a.md'); write(base / 'extra-prompts/drop-b.md')
    write(agent / 'settings.json', json.dumps({
        'skills': [str(base / 'extra/set'), '~/tilde', 'skills/one/SKILL.md', '-skills/nested/deep', '+skills/one', '!glob*', '!**/tilde/t1', '+skills/globbed/SKILL.md', '!e?'],
        'prompts': [str(base / 'extra-prompts'), '*.md', '!drop-*', '!deeper/**'],
        'themes': [str(agent / 'themes/t.json')]}))
    write(project / '.pi/settings.json', json.dumps({'skills': ['-skills/ps', '!{r,s}'], 'prompts': ['-prompts/pp.md'], 'themes': ['!*.json']}))
    return home, agent, project

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--runner', default='build/package-manager.js')
    parser.add_argument('--threads', default='1')
    args = parser.parse_args()
    runner = str(Path(args.runner).resolve())
    command = ['bun', runner] if runner.endswith('.js') else [runner, '--threads', args.threads, '--']
    base = Path(tempfile.mkdtemp(prefix='pi-package-manager-')).resolve()
    home, agent, project = fixture(base)
    env = dict(os.environ, HOME=str(home))
    expected = subprocess.run(['bun', str(ROOT / 'tests/package_manager_reference.ts'), str(project), str(agent)], cwd=UPSTREAM, env=env, capture_output=True, text=True, timeout=120)
    assert expected.returncode == 0, expected.stderr
    actual = subprocess.run(command + [str(project), str(agent)], cwd=project, env=env, capture_output=True, text=True, timeout=300)
    assert actual.returncode == 0, actual.stderr[-2000:]
    want, got = json.loads(expected.stdout), json.loads(actual.stdout.strip().splitlines()[-1])
    checks = 0
    for kind in ('skills', 'prompts', 'themes'):
        assert got[kind] == want[kind], (kind, json.dumps(want[kind], indent=1), json.dumps(got[kind], indent=1))
        checks += len(want[kind])
    print('package-manager: %d resolved resources match' % checks)

main()
