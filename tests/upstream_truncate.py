"""Port of packages/agent/test/harness/truncate.test.ts at the pinned pi-mono.

Preserves all nine named tests, including the exhaustive and seeded UTF-16
surrogate fuzz cases. Python only drives the compiled native Bend functions.
"""
import json
import subprocess
import tempfile

cases = [
    ("counts UTF-8 bytes without Node Buffer", "aé🙂\nb", 100, 10,
     {"head": {"truncated": False, "totalBytes": 9, "outputBytes": 9}}),
    ("does not count a trailing newline as an extra line", "line\nline\nline\n", 100, 3,
     {"head": {"truncated": False, "totalLines": 3, "outputLines": 3}, "tail": {"truncated": False, "totalLines": 3, "outputLines": 3}}),
    ("truncates head on UTF-8 byte limits without partial lines", "éé\nabc", 4, 10,
     {"head": {"content": "éé", "truncated": True, "truncatedBy": "bytes", "outputBytes": 4, "firstLineExceedsLimit": False}}),
    ("reports head truncation when the first line exceeds the byte limit", "éé\nabc", 3, 10,
     {"head": {"content": "", "truncated": True, "truncatedBy": "bytes", "firstLineExceedsLimit": True}}),
    ("truncates tail on UTF-8 boundaries when only a partial last line fits", "aé🙂b", 5, 10,
     {"tail": {"content": "🙂b", "truncated": True, "truncatedBy": "bytes", "lastLinePartial": True, "outputBytes": 5}}),
    ("truncates an oversized single line with a trailing newline", "X" * 300_000 + "\n", 1024, 100,
     {"tail": {"content": "X" * 1024, "outputBytes": 1024, "outputLines": 1, "lastLinePartial": True, "truncatedBy": "bytes"}}),
    ("drops an oversized trailing character when it cannot fit in tail byte limit", "abc🙂", 3, 10,
     {"tail": {"content": "", "truncated": True, "truncatedBy": "bytes", "lastLinePartial": True, "outputBytes": 0}}),
]
with tempfile.NamedTemporaryFile(mode="w", suffix=".json") as file:
    json.dump([{"text": text, "bytes": size, "lines": lines} for _, text, size, lines, _ in cases], file)
    file.flush()
    results = json.loads(subprocess.check_output(["build/test-truncate-runner", file.name], text=True, timeout=120))
assert len(results) == len(cases)
for (name, _, _, _, expected), result in zip(cases, results):
    for side, fields in expected.items():
        for field, value in fields.items():
            assert result[side][field] == value, (name, side, field)
    print(f"PASS {name}")

def utf8(text):
    return text.encode("utf-16-le", "surrogatepass").decode("utf-16-le", "replace").encode("utf-8")

def sampled_limits(text):
    size = len(utf8(text))
    return sorted({n for n in [0, 1, 2, 3, 4, 5, 8, size // 2 - 1, size // 2, size // 2 + 1,
                               size - 8, size - 5, size - 4, size - 3, size - 2, size - 1,
                               size, size + 1, size + 4] if n >= 0})

def buffer_tail(text, size):
    data = utf8(text)
    if len(data) <= size:
        # JSON round-trip joins paired UTF-16 units, preserving isolated units.
        return json.loads(json.dumps(text))
    start = len(data) - size
    while start < len(data) and data[start] & 0xC0 == 0x80:
        start += 1
    return data[start:].decode("utf-8")

pending = []
checked = 0

def flush():
    global checked
    if not pending:
        return
    with tempfile.NamedTemporaryFile(mode="w", suffix=".json") as file:
        json.dump(pending, file)
        file.flush()
        actual = json.loads(subprocess.check_output(["build/test-truncate-runner", file.name], text=True, timeout=30))
    assert len(actual) == len(pending)
    for case, result in zip(pending, actual):
        expected = buffer_tail(case["text"], case["bytes"])
        assert result["tail"]["content"] == expected, (repr(case), repr(result["tail"]), repr(expected))
        assert len(utf8(result["tail"]["content"])) <= case["bytes"]
    checked += len(pending)
    pending.clear()

def check_tail(text, limits):
    for size in limits:
        pending.append({"text": text, "bytes": size, "lines": 10})
        if len(pending) == 64:
            flush()

for text in ["a\ud83d", "\ude42b", "a\ude42b", "\ud83d\ud83d\ude42", "\ud83d\ude42\ude42", "👩‍💻"]:
    check_tail(text, range(len(utf8(text)) + 5))
flush()
print("PASS matches Buffer tail truncation semantics for surrogate edge cases", flush=True)

alphabet = ["a", "\u007f", "\u0080", "é", "\u07ff", "\u0800", "中", "\ud7ff", "\ud800", "\ud83d", "\udc00", "\ude42", "🙂", "\ue000", "\uffff"]

def exhaustive(prefix, depth):
    check_tail(prefix, sampled_limits(prefix))
    if depth:
        for character in alphabet:
            exhaustive(prefix + character, depth - 1)

exhaustive("", 3)
seed = 0x12345678

def random():
    global seed
    seed = (seed * 1664525 + 1013904223) & 0xFFFFFFFF
    return seed / 0x100000000

for _ in range(1000):
    text = "".join(alphabet[int(random() * len(alphabet))] for _ in range(int(random() * 80)))
    check_tail(text, sampled_limits(text))
flush()
print(f"PASS matches Buffer tail truncation semantics across deterministic fuzz cases ({checked} byte-limit checks)")
print("upstream truncation: all 9 ported tests passed")
