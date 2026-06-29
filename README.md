# cuFlye

`cuFlye` is an unofficial, Flye-compatible CUDA acceleration project for
long-read genome assembly.

The target is not a clean-room GPU assembler. The target is a Flye-compatible
fork that keeps Flye's CLI, stage contracts, intermediate artifacts, and CPU
implementation as the reference oracle while moving selected hotspot kernels to
CUDA.

## Current Materials

- `CUDA_FLYE_DESIGN.md`: CUDA backend architecture and milestones.
- `GENOMEWORKS_NOTES.md`: source-level notes from NVIDIA GenomeWorks modules.
- `docs/tasks/`: Task Cards for bounded implementation slices.
- `scripts/`, `tools/`, `bench/`: M0 CPU oracle, canonical diff, and profiling
  harness.
- `upstream-flye/`: local research clone of Flye, ignored by this root repo.
- `GenomeWorks/`: local research clone of NVIDIA GenomeWorks, ignored by this
  root repo.

## M0 CPU Oracle

The first implementation milestone is a CPU reference harness. On a target
Linux/DGX host:

```sh
scripts/build_flye_cpu.sh --fetch-upstream
scripts/run_flye_fixture.sh --out-dir out/m0/runs/toy-a
scripts/run_flye_fixture.sh --out-dir out/m0/runs/toy-b
tools/diff_flye_runs.py out/m0/runs/toy-a out/m0/runs/toy-b
bench/profile_flye_cpu.sh --profile-dir out/m0/profiles/toy-hifi
```

Generated runs and profiles live under `out/` and are intentionally ignored.

## Licensing

Original code in this repository is BSD-3-Clause by default.

Files copied from or substantially derived from NVIDIA GenomeWorks must remain
Apache-2.0. Use file-level SPDX identifiers to make mixed-license boundaries
explicit.

See `LICENSE`, `LICENSES/`, and `THIRD_PARTY_NOTICES.md`.
