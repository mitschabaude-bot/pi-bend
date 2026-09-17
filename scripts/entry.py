"""Separate application argv from Bend's generated runtime CLI.

Bend 2.0.4 treats every argv entry as a runtime flag. The native effect
constructor records original argv; the generated runtime receives its own
arguments. Assert the compiler ABI instead of silently patching unknown code.
"""
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
source = path.read_text()
signature = "int main(int argc, char** argv) {"
assert source.count(signature) == 1, "Unsupported Bend generated entry point"
source = source.replace(signature, "static int pb_bend_entry(int argc, char** argv) {")
source += '\nint main(int argc, char **argv) {\n  char *runtime_argv[] = {argv[0], "--threads", "1", NULL};\n  return pb_bend_entry(3, runtime_argv);\n}\n'
path.write_text(source)
