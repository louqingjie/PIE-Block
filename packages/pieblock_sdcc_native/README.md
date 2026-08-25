# PIE-Block Android SDCC FFI

This package owns the versioned C ABI and Android lifecycle for the in-process
MCS-251 toolchain. It deliberately does not execute compiler binaries from a
writable application directory.

The ABI wrapper, request ownership, event queue, cancellation and single-build
mutex are implemented. `pieblock_sdcc_pipeline.c` is the integration seam for
the preprocessor, compiler, assembler and linker stages from the pinned
`sdcc-c251` fork.

The current integration seam deliberately returns `PB_SDCC_UNAVAILABLE` until
all four stages are linked and pass the Windows/Android byte-for-byte golden
tests. This prevents an incomplete native port from being mistaken for a valid
firmware compiler.

## Fixed baseline

- SDCC fork commit: `912a589d4080c9cd5c5c1faf871c62dd5023580d`
- FFI ABI: `3`
- Android API: `24`
- NDK: `28.2.13676358` (Flutter 3.47.1's Android plugins require this newer
  NDK; it supersedes the originally proposed 27.3 pin)
- ABIs: `arm64-v8a`, `x86_64`

The ARM64 feasibility build has compiled `sdcpp`, the MCS-251 `sdcc` frontend,
`sdas251`, and `sdld` with the NDK. Those executable-shaped probe outputs are
never packaged. The release gate remains conversion of their entry points,
error exits, logging and process-global state into repeatable library calls.

## Licensing

Android distribution code in this package is GPL-3.0-or-later. `LICENSE`
contains GPLv3. Components imported from the SDCC fork retain their own source
headers and license notices; see `THIRD_PARTY_NOTICES.md`.
