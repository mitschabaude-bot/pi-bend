# Directory metadata primitives

`patches/bend-directory-metadata.patch` adds `Directory.read_bytes(path)` and `File.kind(path)` to Base. Apply it after the existing filesystem patches in a private compiler checkout; it changes only Base declarations and OS effect files, with no compiler changes. No shared toolchain was installed during validation.

`Directory.read_bytes` returns an owned list of `(raw filename bytes, kind code)` pairs in enumeration order, excluding `.` and `..`. Codes are other=0, regular file=1, directory=2 and symbolic link=3. Native enumeration uses `opendir`/`readdir` and closes the directory before returning its snapshot. Filesystems reporting `DT_UNKNOWN` use `fstatat(..., AT_SYMLINK_NOFOLLOW)` for that entry; all other entries avoid individual stat calls. `File.kind` follows symlinks using `stat` and never opens file contents. Missing paths, permission failures, symlink loops and invalid embedded NUL paths return OS errors.

The cohesive filesystem module exposes `FileKind`, `DirectoryEntry{name,kind}`, `readDirectory` and `fileKind`. It decodes filenames as strict UTF-8 while preserving a leading BOM. Invalid filename bytes remain available through the raw primitive and produce `InvalidPathEncoding` through the typed wrapper. Consumers decide whether to sort; the primitive preserves enumeration order rather than copying Node's separate `readdirSync` sorting behavior.

The hosted implementation uses synchronous OS metadata calls. Its directory handle is closed on both success and failure. Latin-1 is used only as a reversible byte transport for filename bytes: Bun 1.4.0 returns bare Buffers rather than Dirents for `opendirSync({encoding:"buffer"})`, losing entry types; `encoding:"latin1"` retains typed Dirents and roundtrips every byte. Filename interpretation remains in Bend.

```sh
patch -p1 < /path/to/pi-bend/patches/bend-directory-metadata.patch
BEND=/path/to/private/bend2/main.ts BEND_TUS=8 sh scripts/build-pure.sh tests/filesystem-directory.bend build/filesystem-directory
/path/to/private/bend2/main.ts tests/filesystem-directory.bend -o build/filesystem-directory.js
python3 tests/filesystem_directory_check.py
```

Bun and optimized native one/four workers each pass 35 checks covering raw/typed order, empty directories, Unicode/BOM/newline names, invalid UTF-8, file/directory/broken/cyclic links, FIFO/socket classification without opening content, missing/denied/not-directory/NUL paths, 2,048-entry snapshots and 256 same-process snapshot/stat cycles with stable descriptors. The final native fixture was compiled as eight translation units. Unknown-dirent fallback and injected `closedir` failures were not separately forced.

Observed whole-process timings, including startup/reporting: 256 cycles took 56 ms on Bun and 10–11 ms native; a typed 2,048-entry snapshot took 90 ms on Bun and 14–15 ms native. Descriptor counts stayed 8→8 hosted and 6→6 native. These are scope-specific measurements, not a claim about all filesystems or a comparison with a prior implementation.
