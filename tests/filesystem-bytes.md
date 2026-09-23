# Exact file sizes and owned binary writes

`patches/bend-filesystem-bytes.patch` adds `File.size_bytes(path)` (following symlinks, returning exact unsigned high/low size words), `File.write_bytes(file, bytes)` (retaining the owned handle on every outcome), and exclusive `File.open_mode(path, "wx", permissions)`. Filesystem size conversion to the existing `U64` lives in `filesystem.bend`; policy remains Bend. No compiler/runtime core changes or host path normalization are involved.

Binary writes validate all octets before mutation, drain partial writes, retry EINTR, and reject a zero-progress write with EIO. Each activation resets its error field, so a rejected write followed by a valid write on the retained handle succeeds. Exclusive creation uses O_EXCL and never truncates an existing collision. Stat returns the operating system size without reading content, including zero-size procfs files and sparse sizes above U32.

Apply the patch at a Bend checkout root after the existing filesystem/access patches with `patch -p1 < /absolute/path/patches/bend-filesystem-bytes.patch`. This is an isolated candidate until the parent installs it. Native and Bun use their ordinary OS errors; filename bytes and filesystem policy remain unchanged.

The focused suite passed Bun and optimized native with explicit `--threads 1` and `--threads 4`. It covers files/directories/symlinks/missing/NUL paths, a sparse 32 GiB file, zero through 1 MiB arbitrary binary writes, retained handles after invalid octets and OS errors, /dev/full, read-only handles, exclusive collision and permissions, a real FIFO, and test-only OS write interception for short writes, EINTR and zero progress. Interceptors target only the temporary fixture file and do not modify compiler or production behavior.

```sh
BEND="$PWD/build/bend-files/bend2/main.ts" sh scripts/build-pure.sh tests/filesystem-bytes.bend build/filesystem-bytes
build/bend-files/bend2/main.ts tests/filesystem-bytes.bend -o build/filesystem-bytes.js
python3 tests/filesystem_bytes_check.py -- bun build/filesystem-bytes.js
python3 tests/filesystem_bytes_check.py -- build/filesystem-bytes --threads 1
python3 tests/filesystem_bytes_check.py -- build/filesystem-bytes --threads 4
```

The unaffected `tests/filesystem-access.bend` fixture generates byte-identical native C with the candidate and an otherwise identical candidate copy restoring the original Base/open-mode files. This bounds the patch's effect to programs calling the new primitives or exclusive mode; it is not a general compiler performance claim.
