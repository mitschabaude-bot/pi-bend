"""Exercise resource loading through the CLI runtime's prompt-construction boundary."""
import pathlib, subprocess, tempfile
ROOT=pathlib.Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='pi-runtime-context-') as folder:
    root=pathlib.Path(folder); agent=root/'agent'; repo=root/'repo'; work=repo/'work'; child=work/'child'
    for directory in [agent,repo/'.git',repo/'.git/worktrees/linked',child]: directory.mkdir(parents=True,exist_ok=True)
    (agent/'AGENTS.md').write_text('GLOBAL_CONTEXT_MARKER')
    (repo/'AGENTS.md').write_text('SHADOWED_CONTEXT_MARKER')
    (work/'AGENTS.md').write_text('WORKTREE_CONTEXT_MARKER')
    (child/'AGENTS.override.md').write_text('NEAREST_CONTEXT_MARKER')
    (child/'AGENTS.md').write_text('LOWER_PRIORITY_MARKER')
    (work/'.git').write_text('gitdir: ../.git/worktrees/linked\n')
    (repo/'.git/worktrees/linked/HEAD').write_text('ref: refs/heads/test\n')
    (repo/'.git/worktrees/linked/commondir').write_text('../..\n')
    for label,command in [('bun',['bun','build/runtime-context.js']),('native-1',['build/runtime-context','--threads','1']),('native-4',['build/runtime-context','--threads','4'])]:
        def run(enabled):
            result=subprocess.run(command+[str(child),str(agent),enabled],cwd=ROOT,capture_output=True,text=True,timeout=120)
            assert result.returncode==0,(label,result.stderr)
            return result.stdout,result.stderr
        text,errors=run('on')
        assert not errors and text.index('GLOBAL_CONTEXT_MARKER')<text.index('WORKTREE_CONTEXT_MARKER')<text.index('NEAREST_CONTEXT_MARKER'),(label,text,errors)
        assert 'SHADOWED_CONTEXT_MARKER' not in text and 'LOWER_PRIORITY_MARKER' not in text
        text,errors=run('off')
        assert not errors and all(marker not in text for marker in ['GLOBAL_CONTEXT_MARKER','WORKTREE_CONTEXT_MARKER','NEAREST_CONTEXT_MARKER'])
        (child/'AGENTS.override.md').write_bytes(b'\xff')
        text,errors=run('on')
        assert 'Warning:' in errors and 'AGENTS.override.md' in errors and 'LOWER_PRIORITY_MARKER' in text
        (child/'AGENTS.override.md').write_text('NEAREST_CONTEXT_MARKER')
        print(f'{label}: runtime context layering, shadowing, disable flag and diagnostic fallback passed',flush=True)
