"""Provider ID hashing and Unicode cleanup against the pinned Pi functions."""
from upstream_pin import check_sibling
check_sibling()
import itertools,json,random,subprocess
from pathlib import Path
from schema_literals import string
ROOT=Path(__file__).resolve().parents[1];BUILD=ROOT/'build'
alphabet=['A','\x00','é','\ud800','\udbff','\udc00','\udfff','😀']
cases=['','call_1|fc_abc','system:1:read,write','e\u0301','Hello 🙈 World']
cases += [''.join(xs) for n in [1,2,3] for xs in itertools.product(alphabet,repeat=n)]
rng=random.Random(705)
for _ in range(65):cases.append(''.join(chr(rng.randrange(0x110000)) for _ in range(rng.randrange(1,100))))
expected=json.loads(subprocess.check_output(['node','tests/provider_text_reference.mts'],input=json.dumps(cases),text=True,cwd=ROOT))
lines=['import Base','import ../packages/ai/src/utils/hash.bend as H','import ../packages/ai/src/utils/sanitize-unicode.bend as S','import ../packages/runtime/src/utf16.bend as U','import ../packages/runtime/test/schema.bend as A']
for i,(text,result) in enumerate(zip(cases,expected,strict=True)):
    lines += [f'def case{i}() -> IO(Unit):',f'  A.assertion(String.eq(H.shortHash({string(text)}), {string(result["hash"])}) && U.equal(S.sanitizeSurrogates({string(text)}), {string(result["clean"])}), "provider text {i}")']
groups=[]
for start in range(0,len(cases),35):
    name=f'group{start}';groups.append(name);lines += [f'def {name}() -> IO(Unit):','  do IO<Unit>:']+[f'    case{i}()' for i in range(start,min(start+35,len(cases)))]
lines += ['def main() -> IO(Unit):','  do IO<Unit>:']+[f'    {g}()' for g in groups]+['    A.assertion(String.eq(H.base36(0), "0") && String.eq(H.base36(4294967295), "1z141z3"), "unsigned base36 boundaries")',f'    IO.print("PASS {len(cases)} provider ID hashes and Unicode cleanup comparisons")']
src=BUILD/'provider-text-check.bend';src.write_text('\n'.join(lines)+'\n');out=BUILD/'provider-text-check'
subprocess.run(['sh','scripts/build-pure.sh',str(src),str(out)],cwd=ROOT,check=True)
for threads in ['1','4']:subprocess.run([str(out),'--threads',threads],cwd=ROOT,check=True,timeout=120)
