# flye-cuda

`flye-cuda` is a planning and implementation workspace for a Flye-compatible
CUDA backend.

The target is not a clean-room GPU assembler. The target is a Flye-compatible
fork that keeps Flye's CLI, stage contracts, intermediate artifacts, and CPU
implementation as the reference oracle while moving selected hotspot kernels to
CUDA.

## Current Materials

- `CUDA_FLYE_DESIGN.md`: CUDA backend architecture and milestones.
- `GENOMEWORKS_NOTES.md`: source-level notes from NVIDIA GenomeWorks modules.
- `upstream-flye/`: local research clone of Flye, ignored by this root repo.
- `GenomeWorks/`: local research clone of NVIDIA GenomeWorks, ignored by this
  root repo.

## Licensing

Original code in this repository is BSD-3-Clause by default.

Files copied from or substantially derived from NVIDIA GenomeWorks must remain
Apache-2.0. Use file-level SPDX identifiers to make mixed-license boundaries
explicit.

See `LICENSE`, `LICENSES/`, and `THIRD_PARTY_NOTICES.md`.
