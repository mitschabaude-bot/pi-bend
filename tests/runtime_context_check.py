"""Exercise resource loading through the CLI runtime's prompt-construction boundary."""
import pathlib, subprocess, tempfile
ROOT=pathlib.Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='pi-runtime-context-') as folder:
    root=pathlib.Path(folder); agent=root/'agent'; repo=root/'repo'; work=repo/'work'; child=work/'child'
    for directory in [agent,repo/'.git',repo/'.git/worktrees/linked',child]: directory.mkdir(parents=True,exist_ok=True)
    (agent/'AGENTS.md').write_text('GLOBAL_CONTEXT_MARKER')
    (agent/'skills/marker-skill').mkdir(parents=True)
    (agent/'skills/marker-skill/SKILL.md').write_text('---\nname: marker-skill\ndescription: SKILL_DESCRIPTION_MARKER\n---\nbody\n')
    (repo/'AGENTS.md').write_text('SHADOWED_CONTEXT_MARKER')
    (work/'AGENTS.md').write_text('WORKTREE_CONTEXT_MARKER')
    (child/'AGENTS.override.md').write_text('NEAREST_CONTEXT_MARKER')
    (child/'AGENTS.md').write_text('LOWER_PRIORITY_MARKER')
    (work/'.git').write_text('gitdir: ../.git/worktrees/linked\n')
    (repo/'.git/worktrees/linked/HEAD').write_text('ref: refs/heads/test\n')
    (repo/'.git/worktrees/linked/commondir').write_text('../..\n')
    for label,command in [('bun',['bun','build/runtime-context.js']),('native-1',['build/runtime-context','--threads','1']),('native-4',['build/runtime-context','--threads','4'])]:
        def run(enabled,skills='on'):
            result=subprocess.run(command+[str(child),str(agent),enabled,skills],cwd=ROOT,capture_output=True,text=True,timeout=120)
            assert result.returncode==0,(label,result.stderr)
            return result.stdout,result.stderr
        text,errors=run('on')
        assert not errors and text.index('GLOBAL_CONTEXT_MARKER')<text.index('WORKTREE_CONTEXT_MARKER')<text.index('NEAREST_CONTEXT_MARKER'),(label,text,errors)
        assert 'SHADOWED_CONTEXT_MARKER' not in text and 'LOWER_PRIORITY_MARKER' not in text
        assert '<name>marker-skill</name>' in text and 'SKILL_DESCRIPTION_MARKER' in text and str(agent/'skills/marker-skill/SKILL.md') in text, text
        text,errors=run('on','off')
        assert not errors and 'SKILL_DESCRIPTION_MARKER' not in text
        text,errors=run('off')
        assert not errors and all(marker not in text for marker in ['GLOBAL_CONTEXT_MARKER','WORKTREE_CONTEXT_MARKER','NEAREST_CONTEXT_MARKER'])
        (child/'AGENTS.override.md').write_bytes(b'\xff')
        text,errors=run('on')
        assert 'Warning:' in errors and 'AGENTS.override.md' in errors and 'LOWER_PRIORITY_MARKER' in text
        (child/'AGENTS.override.md').write_text('NEAREST_CONTEXT_MARKER')
        print(f'{label}: runtime context layering, shadowing, disable flag, diagnostic fallback and user skills passed',flush=True)
        # Built-in tool options: settings fill read autoResizeImages and bash
        # commandPrefix/shellPath (upstream _buildRuntime); caller-supplied
        # options win, and bash guidelines follow exposeSessionEnvironment.
        home=str(agent)
        result=subprocess.run(command+['tool-options',str(child),home],cwd=ROOT,capture_output=True,text=True,timeout=120)
        assert result.returncode==0 and not result.stderr,(label,result.stderr)
        lines=result.stdout.split('\n')
        shell=f'{home}/bin/settings-shell'
        assert lines[0]==f'defaults: read.autoResizeImages=false bash.commandPrefix=settings prefix bash.shellPath={shell} bash.exposeSessionEnvironment=unset',(label,lines[0])
        assert lines[1]==f'caller: read.autoResizeImages=false bash.commandPrefix=caller prefix bash.shellPath={shell} bash.exposeSessionEnvironment=false',(label,lines[1])
        guidance='You can inspect PI_* environment variables for current model and session details.'
        prompts=result.stdout.split('--- prompt\n')
        assert len(prompts)==3 and guidance in prompts[1] and guidance not in prompts[2],(label,result.stdout)
        print(f'{label}: runtime built-in tool options from settings and caller passed',flush=True)
