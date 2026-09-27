# Checking scroll layout

The scroll layout fixtures compare native Bend behavior against the pinned upstream `ScrollView` and layout modules. `tests/scroll_view_reference.ts` supplies the state-transition oracle; `tests/scroll_layout_reference.ts` supplies viewport geometry, visible rows and complete ANSI strings. The colored cases check overlay backgrounds, reserved columns, intersected wide characters and isolation of foreground styles, bold text and hyperlinks.

Build the fixture and run all three comparison backends:

```sh
sh scripts/build-incremental.sh tests/scroll-layout.bend build/scroll-layout
python3 tests/scroll_layout_check.py
```

The checker runs the interpreted Bend backend and the native binary with one and four threads. It compares the complete output with the source-pinned reference rather than stripping styles from the colored cases.

For nested layouts, use `tests/layout_tree_check.py`; for prepared/committed TUI frames and scroll/resize transitions, use `tests/tui_layout_check.py`. Compile their corresponding Bend fixtures before running those checkers. Scroll state is an immutable return value: retain the returned tree or view for the next render instead of rendering the previous state again.

The [test inventory](upstream-inventory.json) records upstream suite coverage. [Source review records](../docs/source-coverage-reviews.json) record reviewed implementation coverage and outstanding API gaps.
