"""Compare startup installation of a configured Git package with pinned pi."""

from upstream_pin import UPSTREAM
import argparse
import json
import os
import shutil
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def run(command, *, cwd, env):
    result = subprocess.run(command, cwd=cwd, env=env, text=True, capture_output=True, timeout=120)
    assert result.returncode == 0, result.stderr[-2000:]
    return json.loads(result.stdout.strip().splitlines()[-1])


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--runner', default='build/package-manager-pkg')
    parser.add_argument('--threads', default='1')
    args = parser.parse_args()
    runner = str(Path(args.runner).resolve())
    command = ['bun', runner] if runner.endswith('.js') else [runner, '--threads', args.threads, '--']
    with tempfile.TemporaryDirectory(prefix='pi-package-missing-git-') as temp:
        root = Path(temp)
        remote, agent, project = root / 'remote', root / 'agent', root / 'project'
        for path in (remote, agent, project, root / 'home'):
            path.mkdir()
        ssh = root / 'ssh'
        ssh.write_text('#!/bin/sh\nexec git-upload-pack "$PI_TEST_GIT_REMOTE"\n')
        ssh.chmod(0o755)
        env = {**os.environ, 'HOME': str(root / 'home'), 'GIT_SSH_COMMAND': str(ssh), 'PI_TEST_GIT_REMOTE': str(remote), 'PI_OFFLINE': '0'}
        subprocess.run(['git', 'init', '-b', 'main'], cwd=remote, check=True, capture_output=True)
        subprocess.run(['git', 'config', 'user.name', 'Test'], cwd=remote, check=True)
        subprocess.run(['git', 'config', 'user.email', 'test@example.org'], cwd=remote, check=True)
        skill = remote / 'skills' / 'hello' / 'SKILL.md'
        skill.parent.mkdir(parents=True)
        skill.write_text('---\nname: hello\ndescription: Hello\n---\nbody\n')
        subprocess.run(['git', 'add', '.'], cwd=remote, check=True)
        subprocess.run(['git', 'commit', '-m', 'fixture'], cwd=remote, check=True, capture_output=True)
        source = 'git:git@localhost:test/extension'
        (agent / 'settings.json').write_text(json.dumps({'packages': [source]}))
        checkout = agent / 'git' / 'localhost' / 'test' / 'extension'
        ref = ['bun', str(ROOT / 'tests/package_manager_reference.ts'), str(project), str(agent)]
        upstream_cwd = UPSTREAM / 'packages' / 'coding-agent'
        expected = run(ref, cwd=upstream_cwd, env=env)
        assert checkout.joinpath('skills/hello/SKILL.md').is_file()
        shutil.rmtree(checkout)
        actual = run(command + [str(project), str(agent)], cwd=project, env=env)
        assert actual == expected, (expected, actual)
        assert checkout.joinpath('skills/hello/SKILL.md').is_file()
        shutil.rmtree(checkout)
        env['PI_OFFLINE'] = '1'
        offline = run(command + [str(project), str(agent)], cwd=project, env=env)
        assert offline['skills'] == [] and not checkout.exists(), offline
        print('package startup Git install and offline skip match pi')


if __name__ == '__main__':
    main()
