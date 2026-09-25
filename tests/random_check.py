"""Native SplitMix64 vectors, exact [0,1) conversion, and seed-source failures."""
import random,struct,subprocess,sys,tempfile
from pathlib import Path
from bend_toolchain import BEND
ROOT=Path(__file__).resolve().parents[1]
if '--no-build' not in sys.argv:
 subprocess.run(['flock', '/tmp/pi-bend-build.lock', sys.executable,'scripts/run-rss-guarded.py','--stats','build/random-build.json','--','sh','scripts/build-pure.sh','packages/runtime/test/random.bend','build/random'],cwd=ROOT,check=True)
subprocess.run([BEND,'packages/runtime/test/random.bend','-o','build/random.js'],cwd=ROOT,check=True)
subprocess.run(['flock', '/tmp/pi-bend-build.lock', 'clang','-O2','tests/random_reference.c','-o','build/random-reference'],cwd=ROOT,check=True)
rng=random.Random(64053)
seeds=[0,1,2**32-1,2**32,2**64-1,*[rng.getrandbits(64) for _ in range(27)]]
for threads,command in [('1',[str(ROOT/'build/random'),'--threads','1']),('4',[str(ROOT/'build/random'),'--threads','4']),('Bun',[str(Path.home()/'.bun/bin/bun'),str(ROOT/'build/random.js')])]:
 def run(*args):
  p=subprocess.run([*command,*map(str,args)],cwd=ROOT,capture_output=True,text=True,check=True,timeout=10)
  assert not p.stderr,p.stderr
  return p.stdout
 for seed in seeds:
  words=[str(seed>>32),str(seed&0xffffffff),'128']
  expected=subprocess.check_output([str(ROOT/'build/random-reference'),*words],text=True)
  assert run('s',*words)==expected,(threads,seed)
 for seed in [0,1,2**64-1]:
  words=[str(seed>>32),str(seed&0xffffffff),'128']
  expected=subprocess.check_output([str(ROOT/'build/random-reference'),*words],text=True).splitlines()
  assert sorted(run('c',*words).splitlines())==sorted(expected),(threads,seed,'concurrent')
 for word in [0,1,2047,2048,2049,2**63,2**64-2048,2**64-1]:
  bits=struct.unpack('>II',struct.pack('>d',(word>>11)*2**-53))
  assert run('u',word>>32,word&0xffffffff)==f'{bits[0]}:{bits[1]}\n'
 with tempfile.TemporaryDirectory(dir=ROOT/'build',prefix='random-seed-') as directory:
  folder=Path(directory)
  for size in range(8):
   path=folder/f'short-{size}';path.write_bytes(bytes(range(size)))
   assert run('f',path)==f'short {size}\n'
  path=folder/'seed';path.write_bytes(bytes([0,255,128,1,2,3,4,5]))
  assert run('f',path)=='seed 16744449:33752069\n'
  assert run('f',folder/'missing').startswith('error ')
  assert run('f',folder).startswith('error ')
 for _ in range(8):
  line=run('r').strip();assert line.startswith('random '),line
  hi,lo=map(int,line[7:].split(':'));value=struct.unpack('>d',struct.pack('>II',hi,lo))[0]
  assert 0<=value<1,value
 print(threads,'threads: 4096 PRNG vectors, 384 concurrent draws, conversion boundaries and seed IO PASS')
