# PIE-Block Android SDCC native bridge

This package owns C ABI 5 and the Android multi-process bridge for the embedded
MCS-251 toolchain. Flutter never loads the compiler library.

- `:compiler_coordinator` owns one complete build, foreground notification,
  scheduling, cancellation, logs and result validation.
- A fresh `:compiler_worker` handles exactly one compile unit or the final link,
  then exits after coordinator acknowledgement.
- Coordinator protocol is 2; worker protocol is 1.
- Both `arm64-v8a` and `x86_64` are built from the pinned SDCC stage object.
- No `sdcc`, `sdcpp`, `sdas251` or `sdld` executable is packaged or extracted.

Debug builds enable the single-stage capability for device verification.
Release remains gated until Windows/Android byte-for-byte goldens, failure
isolation, both ABIs and hardware smoke tests pass. There is no user override.

## Fixed baseline

- SDCC fork: `912a589d4080c9cd5c5c1faf871c62dd5023580d`
- C ABI: 5
- Coordinator AIDL: 2
- Worker AIDL: 1
- Android API: 24
- NDK: 28.2.13676358
- ABIs: `arm64-v8a`, `x86_64`

`tools/build_android_sdcc_stages.ps1` reproducibly creates namespace-isolated
stage objects. Production CMake links them into `libpieblock_sdcc_native.so`.
The embedded host only accepts driver-generated dispatches to the embedded
preprocessor, assembler and linker and rejects unknown tools.

## Licensing

Android distribution code in this package is GPL-3.0-or-later. See `LICENSE`
and `THIRD_PARTY_NOTICES.md`. Components retained from the pinned SDCC fork keep
their original source headers and license notices.
