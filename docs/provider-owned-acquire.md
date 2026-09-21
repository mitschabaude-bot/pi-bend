# Lazy runtime acquisition

`provider-owned-acquire.run` executes preparation before initializing runtime dependencies. Its preparation action can include the existing payload hook. A preparation failure skips initialization entirely; an initialization failure skips acquisition. Both retain their typed causes in distinct error variants.

Acquisition receives an affine runtime and returns a runtime alongside its response result. Failure retires the returned runtime before exposing the request cause. Success transfers runtime and response into one affine owner. `release` closes the response first, then retires the runtime even when response closure returns an error, and preserves that close result. No mutable cell stores ownership for later recovery.

[Five generic laws](proof-validation/2026-09-21-provider-owned-acquire-standalone.json) establish these boundary contracts for arbitrary payload/error types, affine owner types and effect programs. They have no unsafe annotations and are included in the [502-law root gate](proof-validation/2026-09-21-owned-provider.json). They do not prove that a caller's acquisition action returns the original runtime or that its supplied retirement program closes every external resource; concrete adapters must establish those properties.

The [runtime record](runtime-validation/2026-09-21-provider-owned-acquire.json) checks fifteen distinct preparation/initialization/request/close traces, repeated four times per process on plain/audited native one/four threads and Bun. Runtime and response owners hold real channel-backed references. Assertions check payload forwarding, failure ordering, original error causes, response-before-runtime closure and zero remaining audited channels/IO after repeated reuse.

The concrete Responses provider still needs to select the payload once, preserve its original preparation/grammar metadata, initialize the native runtime lazily, and carry both runtime and response through processing. This module supplies ownership composition; it does not itself install the system runtime or complete the public provider.
