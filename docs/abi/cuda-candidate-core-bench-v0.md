# cuFlye CUDA Candidate Core Benchmark v0

Status: active

Introduced: M1j

Scope: standalone benchmark for the candidate-generation equality-scan core.

## Purpose

M1j is the first performance gate. It intentionally benchmarks a narrow core:
given precomputed query lookup keys and index lookup keys, count equality
matches over the query/index pair space.

This is not a full Flye benchmark. It excludes FASTQ parsing, full index
construction, candidate TSV serialization, CPU chaining, graph construction,
and polishing. Its purpose is to determine whether the parallel candidate scan
itself has crossed the point where CUDA is faster than a single-process CPU
oracle under identical count semantics.

## Runtime Contract

The benchmark accepts:

- `--queries N`;
- `--index-entries N`;
- `--key-space N`;
- `--trials N`;
- `--warmup-trials N`;
- `--device N`;
- `--threads-per-block N`;
- `--blocks N`;
- `--json-output PATH`.

It must:

- generate deterministic query and index key arrays;
- compute a CPU match count and timing;
- compute a CUDA match count and timing;
- fail if CPU and CUDA counts differ;
- report best and average timings;
- report CPU-vs-GPU speedup for kernel-only and total GPU timed paths.

## Benchmark Boundary

`candidate_core_gpu_faster_than_cpu=true` means the bounded candidate equality
scan is faster on CUDA for the measured dimensions. It does not mean the whole
Flye assembler is faster yet.
