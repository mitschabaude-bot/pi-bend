# Inverse UTC calendar conversion

`calendar-inverse.fromEpochMilliseconds` converts signed millisecond words to literal-year `Calendar.CivilTime` for years 0000–9999. It shifts the epoch into a nonnegative day count, divides in exact U64 arithmetic, searches the bounded year range, and selects the month. Production uses no host date conversion.

Out-of-range bit patterns return `OutOfRange`. Before returning a date, it runs the existing calendar validator and compares the re-encoded timestamp with the original words. Failed reconstruction returns `ReconstructionMismatch`, an internal consistency failure.

The [runtime evidence](runtime-validation/2026-09-21-calendar-inverse.json) checks 5,640 values on native one/four threads and Bun against an independent UTC reference. It covers endpoints, signed extremes, random valid/invalid epochs, and month-boundary neighbors across year zero and leap centuries. All accepted reference dates produce expected fields without reconstruction mismatches.

The [generic success-round-trip law](proof-validation/2026-09-21-calendar-inverse-standalone.json) passes with four supporting lemmas and no unsafe annotations. It is not yet part of the root gate. This success invariant does not establish that every in-range timestamp succeeds; universal completeness remains separate from the finite reference tests. HTTP-date interpretation and retry integration remain pending.

The [proof-checking investigation](bend-issues/2026-09-21-calendar-proof-normalization.json) retains slow proof forms and diagnostic traces. Moving validation to the public boundary preserves the same success invariant while avoiding expansion of the symbolic search inside the proof. No compiler patch was installed.
