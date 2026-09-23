# Native word segmentation through Input and SettingsList

`tests/text-components-native-word.bend` loads and decodes the actual production ICU78 word-rule, CJK dictionary and Khmer dictionary assets once, creates `WordSegmenter.Context`, and passes it through both components' checked `handleInput` API. No captured lexical fixtures or host segmentation are supplied to Bend. The small shared `Word.nativeSegments` adapter in the existing `tui/word-navigation.bend` maps native segments and typed engine errors into the navigation interface; callers continue to own asset loading and the independent atomic predicate. Component APIs are unchanged.

The 95 source-compared sequences exercise Latin punctuation/paths, Chinese/Japanese/Hangul, Khmer lexical words and joiners/combining marks, mixed scripts, emoji/graphemes, all four word movement/deletion commands, kill/yank and undo. Every operation checks Input text/cursor, SettingsList search text/cursor and selected setting; final states are checked separately. The source oracle runs the pinned upstream Input, SettingsList and navigation code using real ICU78.3 segmentation. It preloads CJK with `日本` to implement the user's approved deterministic Common-mark policy. Native execution starts with twelve `ー` marks before any prior CJK text, covers halfwidth prolonged/voicing marks, and repeats the original mark case after Japanese input in the same context. This validates the loaded context's history independence through actual component editing, beyond raw segment comparisons.

Three additional independently specified sequences require Thai, Myanmar and Lao failures from the engines missing in this three-asset context. Insertion still succeeds. Failed forward/backward word movement and deletion preserve the previous component state; subsequent ordinary start/end movement succeeds, and final text/cursors remain unchanged. These expected typed failures do not substitute source-success results or fabricate segmentation. The adapter preserves `MissingWordEngine{language}` and maps the runtime's internal invalid-state guard to navigation's `InvalidSegments`.

All 98 sequences pass Bun and optimized native with one/four threads. The original captured-source component suites remain separate detailed behavioral coverage; these tests close the native-context integration gap for currently implemented language engines. They do not establish exact Unicode fuzzy scoring, missing language-engine parity or full terminal renderer wiring. When the native context gains another dictionary/model, update the explicit fixture loader and replace that language's missing-engine case with real source comparisons.

```sh
bun "$BEND" tests/text-components-native-word.bend -o build/text-components-native-word.js
BEND="$BEND" BEND_TUS=8 sh scripts/build-pure.sh tests/text-components-native-word.bend build/text-components-native-word
python3 tests/text_components_native_word_check.py
```

The oracle uses the existing `build/input-reference/node_modules/get-east-asian-width` test dependency. Production reads only committed native assets. Context loading remains application-owned; the fixture demonstrates that initialization without introducing a separate production loader/wrapper module.
