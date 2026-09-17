import json
import subprocess

cases = [
    ("", [], []),
    ("abc", ["a", "b", "c"], [1, 1, 1]),
    ("e\u0301", ["e\u0301"], [1]),
    ("中文", ["中", "文"], [2, 2]),
    ("👨‍👩‍👧‍👦🇩🇪👍🏽", ["👨‍👩‍👧‍👦", "🇩🇪", "👍🏽"], [2, 2, 2]),
    ("\t\n\u200b", ["\t", "\n", "\u200b"], [3, 0, 0]),
    ('"\\', ['"', '\\'], [1, 1]),
]
for source, texts, widths in cases:
    result = subprocess.run(["build/test-unicode", source], capture_output=True, text=True, check=True)
    clusters, words = map(json.loads, result.stdout.splitlines())
    assert [x["text"] for x in clusters] == texts, clusters
    assert [x["width"] for x in clusters] == widths, clusters
    assert [x["text"] for x in words if x["word"]] == ["hello", "世界"], words
print("unicode: graphemes, emoji, widths, controls, quoting and word boundaries passed")
