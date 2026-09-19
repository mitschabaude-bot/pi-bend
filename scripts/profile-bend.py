"""Profile an isolated copy of Bend's compiler; never patch the installation.

Linux RSS guard bounds a single profiling process. Logs remain under build/.
Instrumentation anchors fail closed if the installed compiler changes.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import signal
import subprocess
import time

ROOT = Path(__file__).resolve().parents[1]


def replace_once(text, old, new):
    if text.count(old) != 1:
        raise ValueError(f"Compiler instrumentation anchor changed: {old!r}")
    return text.replace(old, new, 1)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    parser.add_argument("--base", type=Path, default=Path.home() / ".bend/current/bend2", help="Compiler tree to copy and instrument; defaults to the installation")
    parser.add_argument("--label", default="compiler")
    parser.add_argument("--smol", action="store_true")
    parser.add_argument("--clear-teles", action="store_true", help="Experiment only: clear telescope memoization at existing memo_gc boundaries")
    parser.add_argument("--gc-passes", action="store_true", help="Experiment only: force Bun GC after each code-generation pass")
    parser.add_argument("--rss-limit-gib", type=float, default=40)
    args = parser.parse_args()
    if not args.label.replace("-", "").replace("_", "").isalnum():
        parser.error("label must contain only letters, digits, hyphens or underscores")
    if args.rss_limit_gib <= 0:
        parser.error("RSS limit must be positive")
    installed = args.base.resolve()
    dest = ROOT / "build/bend-profiles" / args.label
    dest.mkdir(parents=True, exist_ok=False)
    compiler = dest / "bend2"
    shutil.copytree(installed, compiler)
    metadata = {
        "source": str(args.source.resolve()),
        "source_sha256": hashlib.sha256(args.source.read_bytes()).hexdigest(),
        "compiler": str(installed.resolve()),
        "compiler_sha256": hashlib.sha256((installed / "comp.ts").read_bytes()).hexdigest(),
        "compiler_files_sha256": {name: hashlib.sha256((installed / name).read_bytes()).hexdigest()
                                  for name in ["main.ts", "bend.ts", "comp.ts", "base.bend"]},
        "smol": args.smol,
        "clear_teles": args.clear_teles,
        "gc_passes": args.gc_passes,
        "rss_limit_gib": args.rss_limit_gib,
    }
    (dest / "metadata.json").write_text(json.dumps(metadata, indent=2) + "\n")
    main_path = compiler / "main.ts"
    text = main_path.read_text()
    text = replace_once(text, '  await Bend.book_load(book, file, "", seen);',
        '  console.error("PROFILE", JSON.stringify({phase:"load-start",...process.memoryUsage()}));\n'
        '  await Bend.book_load(book, file, "", seen);\n'
        '  console.error("PROFILE", JSON.stringify({phase:"load-end",...process.memoryUsage()}));')
    text = replace_once(text, '  Bend.book_valid(book, base?.order.length ?? 0);',
        '  Bend.book_valid(book, base?.order.length ?? 0);\n'
        '  console.error("PROFILE", JSON.stringify({phase:"validate-end",...process.memoryUsage()}));')
    main_path.write_text(text)
    comp_path = compiler / "comp.ts"
    text = comp_path.read_text()
    if args.clear_teles:
        text = replace_once(text, '  [OPENS, USES, FOLDS, SPINES, CONSTS].forEach((m) => m.clear());',
            '  [OPENS, USES, FOLDS, SPINES, CONSTS, TELES].forEach((m) => m.clear());')
    text += '''
let profilePass = 0;
function profileMark(phase: string, extra: object = {}): void {
  console.error("PROFILE", JSON.stringify({phase, pass:profilePass,
    time:Date.now(), ...process.memoryUsage(), probes:PROBES.length,
    teles:TELES.size, opens:OPENS.size, uses:USES.size, folds:FOLDS.size,
    spines:SPINES.size, consts:CONSTS.size, ...extra}));
}
'''
    text = replace_once(text, '  const cb = carb_book(book, ["main", ...RUNTIME_ADTS]);',
        '  profileMark("carb-start");\n'
        '  const cb = carb_book(book, ["main", ...RUNTIME_ADTS]);\n'
        '  profileMark("carb-end", {defs:SRCS.size});')
    text = replace_once(text, '      compile_def(fl, k, tld);',
        '      const started = Date.now();\n'
        '      compile_def(fl, k, tld);\n'
        '      profileMark("def-end", {name:k, ms:Date.now()-started, segments:fl.segs.length});')
    text = replace_once(text, '    fl = pass(done_defs(cb).reverse());',
        '    ++profilePass; profileMark("pass-start");\n'
        '    fl = pass(done_defs(cb).reverse());\n'
        '    profileMark("pass-end", {segments:fl.segs.length, own:cb.own.size, hot:cb.hot.size, stat:cb.stat.size});')
    if args.gc_passes:
        text = replace_once(text, '    profileMark("pass-end", {segments:fl.segs.length, own:cb.own.size, hot:cb.hot.size, stat:cb.stat.size});',
            '    profileMark("pass-end", {segments:fl.segs.length, own:cb.own.size, hot:cb.hot.size, stat:cb.stat.size});\n'
            '    Bun.gc(true); profileMark("pass-after-gc");')
    comp_path.write_text(text)
    bun = shutil.which("bun") or str(Path.home() / ".bun/bin/bun")
    metadata["bun_version"] = subprocess.check_output([bun, "--version"], text=True).strip()
    (dest / "metadata.json").write_text(json.dumps(metadata, indent=2) + "\n")
    cmd = [bun] + (["--smol"] if args.smol else []) + [
        str(main_path), str(args.source.resolve()), "-o", str(dest / "output.c")]
    start = time.monotonic()
    peak = 0
    child_peak = 0
    stopped = False
    with (dest / "compiler.log").open("w") as log:
        process = subprocess.Popen(cmd, cwd=ROOT, stdout=log, stderr=log)
        stop_time = None
        try:
            while True:
                pid, status, usage = os.wait4(process.pid, os.WNOHANG)
                if pid:
                    process.returncode = os.waitstatus_to_exitcode(status)
                    child_peak = usage.ru_maxrss * 1024
                    break
                try:
                    status = Path(f"/proc/{process.pid}/status").read_text()
                    rss = next(int(line.split()[1]) * 1024 for line in status.splitlines() if line.startswith("VmRSS:"))
                    peak = max(peak, rss)
                    if rss > args.rss_limit_gib * 1024**3 and not stopped:
                        stopped = True
                        try:
                            os.kill(process.pid, signal.SIGTERM)
                        except ProcessLookupError:
                            pass
                        stop_time = time.monotonic()
                except (FileNotFoundError, ProcessLookupError, StopIteration):
                    pass
                if stop_time is not None and time.monotonic() - stop_time > 15:
                    try:
                        os.kill(process.pid, signal.SIGKILL)
                    except ProcessLookupError:
                        pass
                time.sleep(0.5)
        finally:
            if process.poll() is None:
                process.kill()
                process.wait()
    result = {"seconds": time.monotonic() - start, "sampled_peak_rss_bytes": peak,
              "peak_rss_bytes": child_peak,
              "rss_guard_stopped": stopped, "returncode": process.returncode}
    (dest / "result.json").write_text(json.dumps(result, indent=2) + "\n")
    print(json.dumps({"directory": str(dest), **result}), flush=True)
    raise SystemExit(2 if stopped else process.returncode)


if __name__ == "__main__":
    main()
