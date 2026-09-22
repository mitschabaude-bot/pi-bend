# Stat-only regular-file predicate

`patches/bend-file-is-file.patch` adds `File.is_file(path: String) -> IO(Result<&1,&1,U32 & String,Bool>)`. Native POSIX uses `stat` and `S_ISREG`; Bun uses `statSync(...).isFile()`. Both follow symbolic links and return ordinary OS errors. Neither opens content. Filename bytes are preserved, embedded NUL is rejected with EILSEQ, and no normalization or executable-search policy enters the primitive.

Apply at a Bend checkout root using `patch -p1 < /absolute/path/patches/bend-file-is-file.patch` after `bend-filesystem-bytes.patch`. Candidate only: the parent owns shared installation. Existing primitive behavior and compiler/runtime core are unchanged; the unaffected filesystem-access fixture emits byte-identical native C before/after the additive declaration.

The focused fixture passed Bun and optimized native with explicit one/four worker counts. It covers an unreadable regular file, a symlink to it, directory/directory symlink, FIFO/FIFO symlink without any reader or writer, socket, device, missing path, dangling symlink, and a subsequent successful query after failures. The timeout-backed FIFO case and unreadable-file success establish metadata inspection without content opening. No parent environment or real account files are changed.

```sh
build/bend-files/bend2/main.ts tests/filesystem-is-file.bend -o build/filesystem-is-file.js
BEND="$PWD/build/bend-files/bend2/main.ts" sh scripts/build-pure.sh tests/filesystem-is-file.bend build/filesystem-is-file
python3 tests/filesystem_is_file_check.py -- bun build/filesystem-is-file.js
python3 tests/filesystem_is_file_check.py -- build/filesystem-is-file --threads 1
python3 tests/filesystem_is_file_check.py -- build/filesystem-is-file --threads 4
```
