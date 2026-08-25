# Android SDCC third-party notices

PIE-Block's Android compiler is based on the `sdcc-c251` fork at commit
`912a589d4080c9cd5c5c1faf871c62dd5023580d`.

The selected source set contains components under different compatible free
software licenses. Every imported file keeps its original copyright and
license header. The release source archive and application notice screen must
include the exact notices from the pinned source tree, including:

- SDCC compiler and ports: GNU GPL, as stated by each source file.
- GCC-derived preprocessor (`support/cpp`): GNU GPLv3 or later, with the
  notices present in that directory.
- ASxxxx assembler/linker (`sdas`): the notices present in the corresponding
  source files.
- Target headers and runtime libraries (`device`): their per-file notices and
  runtime-library exception where applicable.
- `libiberty`: the license terms in the pinned `support/sdbinutils` source.

No Windows `.exe` from `vendor/sdcc-toolchain/bin` is included in an Android
APK or App Bundle. Official releases must publish the matching complete source
tag and reproducible build instructions alongside the binary artifact.
