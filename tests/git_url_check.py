"""upstream git-ssh-url.test.ts plus parseGitUrl differential cases.

Runs tests/git-ssh-url.bend's named upstream cases, then compares its
parseGitUrl with the pinned upstream function (and its hosted-git-info
9.0.3 dependency) on a generated corpus of hosted, scp, protocol and
shorthand sources, refs, credentials, encodings and unsafe paths.
Usage: python3 tests/git_url_check.py [build/git-ssh-url.js] [build/git-ssh-url]
"""
import itertools, json, os, pathlib, random, subprocess, sys

root = pathlib.Path(__file__).resolve().parents[1]
js = sys.argv[1] if len(sys.argv) > 1 else 'build/git-ssh-url.js'
native = sys.argv[2] if len(sys.argv) > 2 else 'build/git-ssh-url'

fixed = [
    'https://github.com/user/repo', 'ssh://git@github.com/user/repo', 'https://github.com/user/repo@v1.0.0',
    'git:git@github.com:user/repo', 'git:github.com/user/repo', 'git:git@github.com:user/repo@v1.0.0',
    'git:git@evil.example:../../victim/repo', 'https://evil.example/..%2F..%2Fvictim/repo', 'https://evil.example/..%2F..%2Fvictim/repo%',
    'git:git@evil.example:/absolute/repo', 'git:git@evil.example:user\\repo/name',
    'git@github.com:user/repo', 'github.com/user/repo', 'user/repo', '', ' ', 'git:', 'git: ', 'git:user/repo',
    'git:github:user/repo', 'git:gitlab:group/sub/project', 'git:bitbucket:team/repo', 'git:gist:abc123', 'git:sourcehut:~user/repo',
    'git:gist.github.com/abc123', 'https://gist.github.com/abc123', 'https://gist.github.com/user/abc123', 'https://gist.github.com/user/abc123/raw',
    'https://gitlab.com/group/sub/project.git', 'https://gitlab.com/group/project/-/tree/main', 'https://gitlab.com/g/p/archive.tar.gz',
    'https://bitbucket.org/team/repo/get/x.tar.gz', 'https://git.sr.ht/~user/repo', 'https://git.sr.ht/~user/repo/archive/x.tar.gz',
    'https://github.com/user/repo/tree/main', 'https://github.com/user/repo/tree', 'https://github.com/user/repo/blob/main/x',
    'https://github.com/user/repo.git', 'https://github.com/user/repo.git#v2', 'https://github.com/user/repo#v2', 'https://github.com/user/repo@v1#v2',
    'https://www.github.com/user/repo', 'HTTPS://GitHub.com/User/Repo', 'https://user:pass@github.com/user/repo', 'git+ssh://git@github.com/user/repo',
    'git:git+ssh://git@github.com/user/repo', 'git:git+https://github.com/user/repo', 'git://github.com/user/repo', 'http://github.com/user/repo',
    'https://example.com/user/repo', 'https://example.com/user/repo@main', 'https://example.com:8443/user/repo.git@v1', 'https://example.com/a/b/c',
    'https://example.com/user', 'https://example.com/user/repo?x=1@y', 'https://example.com/user/repo@', 'https://example.com/user/@ref',
    'ssh://git@example.com:2222/user/repo', 'git:git@example.com:user/repo.git', 'git:git@example.com:user/repo@feature/x',
    'git:example.com/user/repo', 'git:localhost/user/repo', 'git:localhost/user/repo@v1', 'git:server/user/repo', 'git:192.168.1.1/user/repo',
    'git:example.com/user', 'git:example.com/user/repo/', 'git:example.com//user/repo', 'git:git@example.com:user', 'git:git@:user/repo',
    'git:git@host:user/repo\nx', 'https://example.com/%75ser/repo', 'https://example.com/user%2Frepo/x', 'https://ex%41mple.com/user/repo',
    'https://example.com/user/repo%zz', 'https://bücher.example/user/repo', 'https://[::1]/user/repo', 'git:[::1]/user/repo',
    '  https://github.com/user/repo  ', 'git:  github.com/user/repo', 'GIT:github.com/user/repo', 'Git://github.com/user/repo',
    'https://github.com/user/repo#', 'https://github.com/user/repo#semver:^1.0.0', 'git:github.com/user/repo#main', 'git:user/repo#main',
    'git:user/repo@main', 'git:github:user/repo@v1', 'git:github:user/repo#v1', 'git:git@github.com:user/proj@x@y', 'https://github.com/us%er/repo',
    'https://github.com/user/re%20po', 'git:git@github.com:user/repo#v3', 'git:github.com:user/repo', 'git:gitlab.com/g/s/p@v1',
    'git:git@gitlab.com:g/s/p.git', 'https://gitlab.com/g', 'https://github.com/user', 'https://github.com/', 'https://github.com',
    'git:github.com', 'git:.dot/user/repo', 'git:/abs/user/repo', 'git:user@host:repo/x', 'git:a:b@c:d/e', 'git:user:pass@github.com:u/r',
    'git:github.com/user/repo with space', 'https://github.com/user/repo\t', 'git:git@github.com:user/repo/', 'https://codeberg.org/user/repo',
    'git:codeberg.org/user/repo@v1.2', 'ssh://example.com/user/repo', 'ssh://git@example.com/~user/repo', 'git://example.com/user/repo.git',
]


def generated(count: int) -> list:
    rng = random.Random(7)
    prefixes = ['', 'git:', 'git: ', 'https://', 'http://', 'ssh://', 'git://', 'git+ssh://', 'git:git@', 'git:https://', 'git:ssh://git@', 'github:', 'git:github:', 'git:gitlab:']
    hosts = ['github.com', 'www.github.com', 'gitlab.com', 'bitbucket.org', 'gist.github.com', 'git.sr.ht', 'example.com', 'localhost', 'host', 'Example.COM', 'user@github.com', 'a:b@example.com', 'example.com:22', '']
    seps = ['/', ':', '//']
    paths = ['user/repo', 'user/repo.git', 'group/sub/project', 'user', 'user/repo/tree/main', 'user/repo/tree', '../x/y', 'u%2Fx/y', 'u/r%', '~u/r', 'u/r/', 'u//r', '.git', 'u/.git']
    refs = ['', '@v1', '@main', '#v2', '@a#b', '@', '#', '@feat/x', '#semver:^1']
    out = set()
    while len(out) < count:
        out.add(rng.choice(prefixes) + rng.choice(hosts) + rng.choice(seps) + rng.choice(paths) + rng.choice(refs))
    return sorted(out)


cases = fixed + generated(600)
env = dict(os.environ)
expected = subprocess.run(['bun', 'tests/git_url_reference.ts'], cwd=root, input=json.dumps(cases), capture_output=True, text=True, env=env, check=True).stdout.splitlines()
assert len(expected) == len(cases)
encoded = [','.join(str(ord(c)) for c in case) for case in cases]
lanes = []
if os.path.exists(root / js):
    lanes.append(('bun', ['bun', js]))
if os.path.exists(root / native):
    lanes += [('native-1', [native, '--threads', '1', '--']), ('native-4', [native, '--threads', '4', '--'])]
assert lanes, 'build tests/git-ssh-url.bend first'
for name, command in lanes:
    result = subprocess.run(command, cwd=root, capture_output=True, text=True, timeout=300)
    lines = result.stdout.splitlines()
    assert result.returncode == 0 and len(lines) == 10 and all(line.startswith('ok ') for line in lines), (name, result.stdout, result.stderr)
    actual = []
    for chunk in range(0, len(encoded), 100):
        run = subprocess.run(command + ['diff'] + encoded[chunk:chunk + 100], cwd=root, capture_output=True, text=True, timeout=300)
        assert run.returncode == 0, (name, run.stderr)
        actual += run.stdout.splitlines()
    mismatches = [(cases[i], expected[i], actual[i] if i < len(actual) else None) for i in range(len(cases)) if i >= len(actual) or actual[i] != expected[i]]
    for case, want, got in mismatches[:20]:
        print('MISMATCH', repr(case), want, got)
    assert not mismatches, (name, len(mismatches))
    print(f'{name}: 10 upstream cases and {len(cases)} differential sources match pinned parseGitUrl')
