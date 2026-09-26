"""plan-mode-utils.test.ts: examples/extensions/plan-mode/utils.bend against the pinned upstream utils.ts.

Every input of the upstream suite (and a few more) runs through both; the upstream suite's assertions hold for
upstream's results, so equal results carry them. markCompletedSteps returns the marked items instead of mutating
them. Build: bun build/bend-native-toolchain/bend2/main.ts tests/plan-mode-utils.bend -o build/plan-mode-utils.js
"""
from upstream_pin import UPSTREAM
import argparse, json, subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
UTILS = UPSTREAM / 'packages/coding-agent/examples/extensions/plan-mode/utils.ts'

SAFE = ['ls -la', 'cat file.txt', 'head -n 10 file.txt', 'tail -f log.txt', 'grep pattern file', "find . -name '*.ts'",
        'git status', 'git log --oneline', 'git diff', 'git branch', 'npm list', 'npm outdated', 'yarn info react',
        'pwd', 'echo hello', 'wc -l file.txt', 'du -sh .', 'df -h', 'rm file.txt', 'rm -rf dir', 'mv old new',
        'cp src dst', 'mkdir newdir', 'touch newfile', 'git add .', "git commit -m 'msg'", 'git push', 'git checkout main',
        'git reset --hard', 'npm install lodash', 'yarn add react', 'pip install requests', 'brew install node',
        'echo hello > file.txt', 'cat foo >> bar', '>file.txt', 'sudo rm -rf /', 'kill -9 1234', 'reboot',
        'vim file.txt', 'nano file.txt', 'code .', 'unknown-command', 'my-script.sh', '  ls -la', '  rm file',
        'cat a < b', 'GIT STATUS', 'git branch -D x', 'curl https://x', 'sed -n 1p f', 'service nginx restart']
CLEAN = ['**bold text**', '*italic text*', 'run `npm install`', 'check the `config.json` file', 'Create the new file',
         'Run the tests', 'Check the status', 'update config', 'This is a very long step description that exceeds the maximum allowed length for display',
         'multiple   spaces   here', '', '**a** and *b* `c`', 'install  THE package', 'Use\tthe tool']
TODO = ["Here's what we'll do:\n\nPlan:\n1. First step here\n2. Second step here\n3. Third step here",
        '**Plan:**\n1. Do something', 'Plan:\n1) First item\n2) Second item', 'Here are some steps:\n1. First step\n2. Second step',
        'Plan:\n1. OK\n2. This is a proper step', 'Plan:\n1. `npm install`\n2. Run the build process',
        'intro plan:  \n  1. **Bold step text** here\n  12) - dash item\n3. /slash item\n4. Update the configuration file for the whole application please']
DONE = ["I've completed the first step [DONE:1]", 'Did steps [DONE:1] and [DONE:2] and [DONE:3]', '[done:1] [DONE:2] [Done:3]',
        'No markers here', '[DONE:abc] [DONE:] [DONE:1]']
MARK = [('[DONE:1] [DONE:3]', '1:0,2:0,3:0'), ('[DONE:1]', '1:0'), ('no markers', '1:0'), ('[DONE:99]', '1:0'), ('[DONE:1]', '1:1')]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--runner', default='build/plan-mode-utils.js')
    parser.add_argument('--threads', default='1')
    args = parser.parse_args()
    runner = str(Path(args.runner).resolve())
    command = ['bun', runner] if runner.endswith('.js') else [runner, '--threads', args.threads, '--']
    cases = [('isSafeCommand', c, '') for c in SAFE] + [('cleanStepText', c, '') for c in CLEAN] + \
            [('extractTodoItems', c, '') for c in TODO] + [('extractDoneSteps', c, '') for c in DONE] + \
            [('markCompletedSteps', text, items) for text, items in MARK]
    expected = json.loads(subprocess.check_output(['bun', str(ROOT / 'tests/plan_mode_utils_reference.ts'), str(UTILS)], input=json.dumps(cases), text=True))
    for (fn, text, items), want in zip(cases, expected):
        out = subprocess.run(command + [fn, text] + ([items] if items else []), capture_output=True, text=True, timeout=120)
        assert out.returncode == 0, (fn, text, out.stderr[-500:])
        got = json.loads(out.stdout.strip().splitlines()[-1])
        assert got == want, (fn, text, got, want)
    print('plan-mode-utils: %d cases match upstream' % len(cases))


main()
