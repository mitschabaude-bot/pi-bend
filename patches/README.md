# Bend compiler patches

`bend-shared-import-namespace.patch` fixes a module-loader issue observed in Bend 2.0.5. A file imported directly and through a sibling package could receive two lexical namespaces when the paths crossed above the entry directory. The loader now reuses a completed file’s established namespace when assigning a local import alias. Active import cycles remain errors. This changes the compiler’s import resolution; it adds no foreign behavior to the Bend executable.

Apply it to the installed compiler source after inspecting compatibility with the installed release:

```sh
patch --forward -p1 -d "$HOME/.bend/current" < patches/bend-shared-import-namespace.patch
python3 tests/module_imports.py
```

The patch is currently applied locally. Bend automatic updates remain enabled, so a future release may remove it or fix the issue upstream. The regression checks both diamond-import orders and cycle rejection; `sh tests/transcript.sh` additionally exercises the real ai/agent/runtime dependency graph. The build script does not silently modify the compiler.
