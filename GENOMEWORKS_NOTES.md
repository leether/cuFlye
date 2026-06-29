# GenomeWorks design notes for cuFlye

Source checkout:

- Repo: `GenomeWorks`
- Remote: `https://github.com/NVIDIA-Genomics-Research/GenomeWorks.git`
- Checked-out branch: `dev`
- Current commit: `baab566885cd9c631f4f941c99d0ce37f9b10ecf`
- Commit date: `2021-08-25`
- Note: third-party dependencies are declared as submodules but were not needed
  for this source-level design pass.

## High-level shape

GenomeWorks is an SDK, not a Flye-like assembler. It exposes libraries plus
sample binaries:

- `cudamapper`: minimizer-based sequence-to-sequence mapping
- `cudapoa`: batched partial-order alignment for consensus and MSA
- `cudaaligner`: batched global alignment
- shared CUDA utilities for device buffers, allocators, streams, and profiling

The strongest architectural lesson is that each module is a bounded service:
host code packages work into batches, kernels process regular data structures,
and results are copied back through explicit typed APIs. That is the right shape
for a Flye CUDA fork.

## cudamapper

Public API:

- `Index`: asynchronous minimizer index over one read interval.
- `Matcher`: turns query/target indices into sorted anchors.
- `Overlapper`: turns anchors into coarse overlaps.

Internal patterns worth copying:

- Split read data into `IndexDescriptor` ranges rather than building one
  unbounded GPU index.
- Separate host batches and device batches. Host batches define reusable cached
  index windows; device batches define what fits on GPU at one time.
- Exploit all-vs-all symmetry by processing only the upper triangle when query
  and target are the same dataset.
- Keep optional host-side index cache so target batches can be reused without
  recomputing.
- Use sorted columnar arrays for minimizer representations, read ids, positions,
  and strand/direction.

Limitations for Flye:

- The public `Overlap` result is too coarse for Flye. It has read ids,
  coordinates, strand, anchor count, and a completion flag. Flye needs its own
  `OverlapRange` semantics: chain score, divergence, overhang rules,
  min-overlap thresholds, optional k-mer match path, complement/reverse forms,
  and repeat-aware filtering.
- cudamapper is minimizer-based. Flye supports both minimizer indexing and
  solid-k-mer behavior under its own config rules, so the GPU backend must
  preserve Flye's selection and filtering semantics.

Flye decision:

- Reuse cudamapper as a design reference for indexing, matching, caching, and
  batching.
- Do not use cudamapper as a drop-in replacement for `OverlapDetector`.
- If code reuse is attempted, start by adapting its index/matcher concepts to
  emit Flye-compatible candidate match lists, then run Flye's own chain/filter
  logic.

## cudaaligner

Public API:

- `Aligner`: queue many query/target pairs, launch `align_all()`, then
  `sync_alignments()`.
- `FixedBandAligner`: configurable band width.
- `Alignment`: exposes CIGAR-like run-length encoded states and edit distance.

Internal patterns worth copying:

- Batch object owns memory, exposes `reset()`, and is reused across batches.
- Results include metadata because GPU execution order may differ from enqueue
  order.
- Device result pointers are exposed for downstream GPU consumers, while host
  alignment objects are available for CPU consumers.
- There is an explicit `is_optimal()` flag for approximate/banded results.

Limitations for Flye:

- cudaaligner is global-alignment/edit-distance oriented.
- Flye currently uses edlib for some divergence checks and ksw2-style scoring
  with match/mismatch/gap-open/gap-extend and dynamic banding for CIGAR in other
  paths.
- Direct replacement can change scoring, optimality, and CIGAR tie-breaking.

Flye decision:

- Good candidate for batched base-level divergence checks where Flye only needs
  edit distance.
- Risky for replacing ksw2 CIGAR-producing paths until a compatibility wrapper
  proves exact scoring and tie-breaking parity.
- Any use must preserve homopolymer compression behavior where Flye currently
  applies it before alignment.

## cudapoa

Public API:

- `Entry`: one sequence plus optional per-base weights.
- `Group`: a POA group, i.e. all sequences for one consensus/MSA unit.
- `Batch`: add POA groups, run `generate_poa()`, then get consensus/MSA/graph.
- `BatchConfig`: explicit maximum sequence size, consensus size, graph nodes,
  matrix dimension, band mode, and sequence count.

Internal patterns worth copying:

- Group variable-size work into multiple batch configurations rather than using
  one global max shape.
- Bin POA groups by estimated capacity to increase parallelism and avoid wasting
  memory on small groups.
- Support per-sequence and per-group status so oversized inputs can be rejected
  or sent to fallback without killing the whole run.
- Pick 16-bit vs 32-bit internal types from upper/lower score and size bounds.
- Expose banding modes: full, static, adaptive, and traceback variants.

Limitations for Flye:

- Flye's polishing is not generic POA only. The current C++ polisher has
  substitution matrices, homopolymer logic, and dinucleotide fixes.
- cudapoa consensus may differ from Flye's bubble correction even if it is
  biologically reasonable.
- Dropping oversized reads/groups is acceptable in a sample app but not
  acceptable silently in Flye exact mode.

Flye decision:

- Strong candidate for an experimental GPU polishing backend, but only behind
  a Flye-compatible scoring adapter and with CPU fallback per bubble.
- The multi-batch binning strategy should be copied for Flye bubbles.
- In exact/deterministic mode, cudapoa output must be checked against Flye's CPU
  bubble consensus before it can replace the CPU result.

## Shared CUDA infrastructure

Useful patterns:

- RAII device buffers tied to allocators and CUDA streams.
- Optional caching allocator over preallocated GPU memory.
- Scoped CUDA device switching.
- NVTX profiling ranges behind a compile-time macro.
- Explicit largest-contiguous-memory discovery before building batches.

Flye decision:

- Add a small local CUDA runtime layer in `src/cuda/` with these same ideas.
- Do not spread raw `cudaMalloc`, `cudaFree`, or stream ownership across Flye's
  assembly/repeat/polishing code.
- Make each GPU backend report:
  - bytes requested
  - bytes granted
  - fallback count
  - stream/device id
  - kernel time and copy time

## Revised Flye CUDA roadmap after reading GenomeWorks

1. M0 stays the same: build upstream Flye, create profiler and canonical
   intermediate-artifact diff harness.
2. M1 should implement a Flye-specific GPU minimizer/k-mer candidate backend,
   borrowing cudamapper's index descriptor, host/device batch, and cache design.
3. M2 should port Flye's own chaining semantics, not call cudamapper overlapper
   directly.
4. M3 can evaluate cudaaligner only for batched edit-distance divergence checks.
5. M4 should prototype bubble polishing with cudapoa-style group binning, but
   not claim replacement until Flye CPU bubble consensus parity is proven.
6. All modules need deterministic output ordering. GenomeWorks often documents
   that GPU output order can differ; Flye exact mode cannot expose that
   nondeterminism to downstream graph logic.

## Bottom line

GenomeWorks is useful as a design library and source of proven CUDA batching
patterns. It is not a ready-made CUDA Flye core. The best path is a Flye-native
backend architecture inspired by GenomeWorks:

- cudamapper inspires `FlyeGpuIndex` and `FlyeGpuMatcher`.
- cudaaligner inspires `FlyeGpuBatchAligner` for divergence checks.
- cudapoa inspires `FlyeGpuBubbleBatcher` for polishing.

The graph resolver remains Flye CPU logic until the overlap/alignment artifacts
are proven equivalent.
