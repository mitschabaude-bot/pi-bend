# PackageManager resolution

`tests/package_manager_check.py` builds isolated project, agent and package trees, then compares `PackageManager.resolve` with pinned pi. It covers settings paths, auto-discovery, metadata, precedence, canonical deduplication, ignore rules, symlinks, package manifests, convention directories, resource filters and extension entries. The paired extension fixture uses `.ts` for pi and `.bend` for the native resolver; the check compares the resulting paths after removing only that suffix.

Build the focused resolver with `bun build/bend-native-toolchain/bend2/main.ts tests/package-manager.bend -o build/package-manager.js` or `BEND_TUS=4 sh scripts/build-pure.sh tests/package-manager.bend build/package-manager`, then run `python3 tests/package_manager_check.py --runner build/package-manager[.js] --threads N`.

`tests/package_manager_missing_git_check.py` checks startup installation and offline skipping of a configured Git package through a local SSH transport. Source parsing, settings normalization, package commands and Git update/removal have their own focused checks. The current coverage and remaining gaps are tracked in `docs/source-coverage-reviews.json` and `tests/upstream-inventory.json`.
