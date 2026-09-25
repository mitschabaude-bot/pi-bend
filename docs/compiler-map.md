# How bend2's C backend works

A map of `bend2/comp.ts` (Bend 2.0.7 plus `patches/`), written from reading
the file whole on 2026-09-25. It records mechanisms and their reasons, so that
compiler patches start from the design rather than from symptoms. Read so far:
all of the compiler part of `comp.ts` and the runtime's heap, term, drop,
task and segment-entry code. Not read yet: `bend.ts` (parser, checker,
elaborator), the runtime's IO, scheduler (`monk`) and `main`.

## Pipeline

1. `carb_book` walks the definitions reachable from `main` and the runtime's
   datatypes. It raises each definition (`def_raise`, turning leading lambdas
   and matches into parameters) and records a source summary per definition
   (`SRCS`): what it refers to, what it calls, and whether it is *flat* (no
   fork, no `!` call, self-calls only in tail position).
2. `compile_book` emits every definition as a *unit*, callees first. The
   emitter is also the analysis (the "facts", below). A unit whose output read
   a fact that grew later is dirty and is emitted again, until nothing is
   dirty. On the CLI this takes about a dozen rounds.
3. The segments reachable from `main` are kept. Tables, spins and segments are
   pasted into the runtime template (`TEMPLATE`), split into `BEND_TUS`
   translation units.

## Values and layouts

- A value is a list of C words (`Val.ws`) with a layout (`Lay`): per word a
  kind (`w32`, `w64`, `box`), and for a sum type its arms with each field's
  word offset. `lay_of` keeps a non-recursive datatype *inline*: a record is
  its fields' words, and a sum is a tag word plus its arms overlaid
  (`lay_pack`). Recursive types, `Array` and `IO.OP` are boxed (one word
  pointing at a heap node).
- `BEND_LAY_MAX` (our layout-cap patch) boxes records wider than 32 words.
  Every live inline word is a separate C variable, and a parameter of each
  segment that holds the value.
- `val_to` converts between layouts, boxing or unboxing as needed. Converting
  a sum emits a branch per arm (`val_arms`).

## Ownership: the facts

The emitter decides where values are copied, borrowed or released while it
emits. Facts only grow, so emission reaches a fixed point:

- `brwl`: a definition's boxed parameters start *borrowed* from their caller.
- `own`: a parameter the definition must own (it stores or returns it).
- `lend`: a borrowed parameter passed on to a callee's borrowed parameter.
- `hot`: a constructor whose nodes may be shared (reference-counted with
  `rfc_seal`) because some value of its type is used twice.
- `stat`: constructors built from constants, placed in the static image.

A variable's last use takes the value; earlier uses `term_keep` it
(`bind_pop`). A binding no longer used in the rest of a branch is released at
the start of that branch (`bind_dead` → `term_sink`), so each arm of a match
releases what that arm does not need.

## Segments

A definition becomes one or more *segments*. On the host each segment is a
`preserve_none` C function, and control passes by `musttail` calls. On a GPU
each is a `case` of one switch.

- **Parameters** are the live words at entry. A segment takes them in the
  shared register bank `r0..rN`.
- **Calls**: a call in tail position is a jump that sets `r0..` and tail-calls
  the callee. A call whose result is needed (`emit_fork`) pushes a *frame*
  (the live words plus the continuation's segment id) on the explicit stack
  and jumps. The callee returns through `WL_RETN`, which pops the
  continuation. The continuation segment (`$k`) reads its held words from its
  frame and the callee's results from `r0..`.
- **Closures** (`$c`): a node holding the captured words. Applying one
  (`FID_CLO_APPLY`) loads the node's words into the bank and adds the
  argument.
- **Forks** (a `let` of several calls): in parallel, a join task (`$j`) with
  a slot per result, plus one task per call. In sequence, the same calls run
  as a chain of continuations.
- **Tasks** (forks and `!` calls): a heap node with the segment's words, a
  continuation and a counter. `FID_ENTER` loads a task into registers and, for
  a continuation, its frame onto the stack. `FID_RESW_T` gives how many words
  go to registers.
- **Spins**: a flat definition called outside tail position becomes a plain C
  function (`INLINE`, or `FAR` when long), called directly with its words as
  C arguments. Its self-calls are a loop.
- **Fusion**: a definition called from exactly one site is emitted inside
  its caller (`emit_fuse`).

Every host segment function has the same signature: the whole bank. So the
widest register-passed segment sets the width of all of them (see the bank
cap in `docs/bend-issues.md`).

## Runtime representation

- A term is 64 bits: a tag (`PAK` packed constructor, `CTR`, `CLO`, `BUF`,
  `TSK`, `ARR`), a 16-bit aux (constructor or segment id), and a 40-bit heap
  location. Bit 63 marks a reference-counted indirection (`rfc_wrap`).
- The heap allocates in power-of-two size classes from per-thread free
  lists (`heap_alloc`, `heap_free`), handing surplus to a shared bank.
- `term_drop` releases a value iteratively. It threads a cursor through the
  nodes being released, holding each node's field count and position in 8
  bits each. Nodes with more fields than that release their fields directly.
- Tables: `CID_ARITY_T` (a constructor's words) and `FID_ARITY_T` (a segment's
  words) are `u8`, or `u16` when some entry needs it. `FID_FLAG_T` marks `!`
  and fork-free segments.

## Where the size of the CLI's C comes from

As measured on 2026-09-25, on 168 MB of C:

- about 57,000 segment functions, each with a signature as wide as the bank
  (166 words), forward-declared in every translation unit for the dispatch
  table. In one unit's preprocessed text, 123 of 312 MB are these signatures;
- string-literal matches, compiled one character at a time: each failure
  path releases every live variable again (`bind_dead` per arm);
- spins (26 MB) and the static-image and root code.
