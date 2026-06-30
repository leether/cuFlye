# cuFlye CUDA K-mer Encode Smoke Prototype v0

Status: active

Introduced: M1h

Scope: standalone CUDA kernel that computes Flye-style 2-bit k-mer
representations, reverse complements, standard-form lookup keys, and then
generates a small candidate-record-v1 TSV from a DNA k-mer fixture.

## Purpose

M1h removes the M1g fixture shortcut where `query_kmer` and `lookup_kmer` were
provided as integers. The GPU now computes:

- forward k-mer representation with Flye's `A=0, C=1, G=2, T=3` encoding;
- reverse-complement representation with Flye's `~base & 3` complement rule;
- standard-form lookup key as `min(forward, reverse_complement)`;
- equality-join candidate records.

It remains standalone. It does not parse FASTQ/FASTA reads, upload Flye's full
`VertexIndex`, or replace the Flye backend stub.

## Binary

Source:

```text
cuda/cuflye_cuda_kmer_encode_smoke.cu
```

Build:

```sh
scripts/build_cuda_kmer_encode_smoke.sh --arch sm_121
```

Default output:

```text
out/m1h/bin/cuflye-cuda-kmer-encode-smoke
```

## Fixture Encoding

Query TSV has no header and exactly three fields:

```text
query_id<TAB>query_pos<TAB>query_kmer_sequence<LF>
```

Index TSV has no header and exactly four fields:

```text
target_id<TAB>target_pos<TAB>target_strand<TAB>target_kmer_sequence<LF>
```

Repetitive-kmer TSV, when provided, has no header and one k-mer sequence per
line.

All sequences must contain only `A/C/G/T` and must match `--kmer-size`.

## Runtime Contract

Required arguments:

- `--kmer-size N`, supported range `1..32`;
- `--queries-tsv PATH`;
- `--index-tsv PATH`;
- `--output-tsv PATH`.

Optional arguments:

- `--repetitive-kmers-tsv PATH`;
- `--cpu-output-tsv PATH`: write a host oracle generated from the same fixture;
- `--device N`: CUDA device id, default from `CUFLYE_CUDA_DEVICE` or `0`;
- `--memory-budget-bytes N`: maximum allowed device allocation;
- `--json-output PATH`: compact runtime manifest.

The prototype must:

- parse DNA k-mer fixture rows into fixed-width structs;
- compute forward k-mer representation on device;
- compute reverse complement and standard form on device;
- preserve the forward query representation in ABI field `kmer`;
- skip repetitive standard-form lookup keys;
- skip trivial same-read/same-position hits;
- preserve duplicate candidate records;
- fail if requested device allocation exceeds the memory budget;
- report `memory_budget_satisfied`;
- pass `tools/validate_candidate_dump.py`;
- pass `tools/diff_candidate_dumps.py` against the host oracle and expected
  fixture.

## Non-Goals

M1h does not:

- parse FASTQ/FASTA reads;
- slide windows across full reads;
- upload Flye's full `VertexIndex`;
- perform device-side target coordinate transforms for reverse-complement index
  construction;
- replace the Flye backend stub;
- claim performance improvement.

The only correctness claim is that CUDA device code can compute Flye-compatible
k-mer representations and standard-form keys for a bounded equality-join
fixture.
