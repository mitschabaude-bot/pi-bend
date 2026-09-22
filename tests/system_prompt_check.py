"""system-prompt.test.ts contracts: empty tools, prefixes, forced prompt,
section mapping, default/custom tool snippets, guideline dedupe, section
validation, cwd normalization and section diffs."""
import pathlib, subprocess
ROOT = pathlib.Path(__file__).resolve().parents[1]
UPSTREAM = ROOT.parent / 'pi-mono'
PREFIX = ROOT / 'build/system-prompt'
source = subprocess.check_output(['git', '-C', str(UPSTREAM), 'show', '46c9de402:packages/coding-agent/src/core/system-prompt.ts'], text=True)
preamble = source[source.index('promptSections.preamble =\n\t\t\t"') + len('promptSections.preamble =\n\t\t\t"'):]
preamble = preamble[:preamble.index('";')]

for backend, command in [('bun', ['bun', str(PREFIX) + '.js']), ('native-1', [str(PREFIX), '--threads', '1']), ('native-4', [str(PREFIX), '--threads', '4'])]:
    def run(*args):
        result = subprocess.run(command + ['--', *args], capture_output=True, text=True, timeout=60)
        assert result.returncode == 0 and not result.stderr, (backend, args, result.returncode, result.stderr)
        return result.stdout[:-1] if result.stdout.endswith('\n') else result.stdout
    def sections(name):
        return dict(line.split('\t', 1) for line in run('sections', name).splitlines())
    empty = run('build', 'empty-tools')
    assert '<tools>\n(none)\n' in empty
    assert 'Show file paths clearly' in empty
    print(f'{backend}: shows (none) for empty tools list; shows file paths guideline even with no tools', flush=True)
    assert empty.startswith(preamble), 'default prefix is exact'
    assert run('build', 'custom-prefix').startswith('You are Exact.\n\n<cwd>')
    assert run('build', 'forced') == 'exact'
    print(f'{backend}: keeps the default and custom prompt prefixes exact; preserves an exact forced prompt', flush=True)
    mapped = sections('sections')
    assert mapped['addendum'] == '<addendum>\\nCustom instructions\\n</addendum>'
    assert mapped['project_context'] == '<project_context>\\nProject-specific instructions and guidelines:\\n\\n<project_instructions path="/tmp/AGENTS.md">\\nProject rules\\n</project_instructions>\\n</project_context>'
    assert list(mapped) == ['preamble', 'tools', 'rules', 'docs', 'addendum', 'project_context', 'cwd']
    print(f'{backend}: maps appended instructions and project context to stable sections', flush=True)
    default = run('build', 'default-tools')
    for line in ['- read: Read file contents', '- bash: Execute bash commands (ls, grep, find, etc.)', '- edit: Make precise file edits with exact text replacement, including multiple disjoint edits in one call', '- write: Create or overwrite files']:
        assert line in default, line
    assert '- Use bash for file operations like ls, rg, find' in default
    assert '- Use read to examine files instead of cat or sed.' in default
    assert '- Use edit for precise changes (edits[].oldText must match exactly)' in default
    assert default.index('Be concise in your responses') < default.index('Show file paths clearly when working with files')
    assert '- Main documentation: /opt/pi/README.md' in default and '- Additional docs: /opt/pi/docs' in default and '- Examples: /opt/pi/examples (extensions, custom tools, SDK)' in default
    print(f'{backend}: includes all default tools when snippets are provided; resolves pi docs under absolute base paths', flush=True)
    custom = run('build', 'custom-snippet')
    assert '- custom_tool: Does custom things' in custom
    assert 'custom_tool' not in run('build', 'missing-snippet')
    print(f'{backend}: includes custom tools only when a promptSnippet is provided', flush=True)
    guided = run('build', 'prompt-guidelines')
    assert guided.count('- Always run tests.') == 1 and '- Prefer small commits.' in guided
    assert guided.index('- Always run tests.') < guided.index('- Be concise in your responses')
    print(f'{backend}: appends, deduplicates and trims promptGuidelines', flush=True)
    assert '- Use bash for file operations like ls, rg, find' in run('build', 'bash-only')
    custom_section = sections('custom-section')
    assert custom_section['memory'] == '<memory>\\nRemember this\\n</memory>' and 'empty' not in custom_section
    assert run('sections', 'bad-section') == 'error:Invalid system prompt section name: Bad Name'
    assert sections('windows-cwd')['cwd'] == '<cwd>\\nC:/work/repo\\n</cwd>'
    print(f'{backend}: custom sections are tagged, empty ones dropped, invalid names rejected, cwd uses forward slashes', flush=True)
    assert run('diff') == 'preamble\tnew\nadded\t<added>\\nhi\\n</added>\nremoved\tnull'
    assert run('diff-same') == 'unchanged'
    print(f'{backend}: diffSystemPromptSections reports changed, added and removed sections', flush=True)
print('system_prompt_check: PASS')
