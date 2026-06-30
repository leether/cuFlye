# cuFlye CUDA K-mer Join Smoke Prototype v0

Status: active

Introduced: M1g

Scope: standalone CUDA kernel that generates a small candidate-record-v1 TSV
from query k-mers and a flattened k-mer index fixture.

## Purpose

M1g is the first prototype where the GPU creates candidate records instead of
copying a CPU candidate sample. It still does not integrate with Flye or build a
real Flye `VertexIndex` on device.

The prototype reads a small, explicit fixture:

- query k-mers;
- flattened target index entries;
- optional repetitive lookup k-mers.

The CUDA kernel performs an exact equality join on lookup k-mer, skips
repetitive lookup k-mers, skips the trivial same-read/same-position hit, and
emits candidate-record-v1 rows.

## Binary

Source:

```text
cuda/cuflye_cuda_kmer_join_smoke.cu
```

Build:

```sh
scripts/build_cuda_kmer_join_smoke.sh --arch sm_121
```

Default output:

```text
out/m1g/bin/cuflye-cuda-kmer-join-smoke
```

## Fixture Encoding

Query TSV has no header and exactly four fields:

```text
query_id<TAB>query_pos<TAB>query_kmer<TAB>lookup_kmer<LF>
```

`query_kmer` is the k-mer representation written to the ABI record.
`lookup_kmer` is the standardized key used for index lookup. This keeps M1g
focused on candidate join semantics while leaving device-side Flye
`Kmer::standardForm()` implementation for a later slice.

Index TSV has no header and exactly four fields:

```text
lookup_kmer<TAB>target_id<TAB>target_pos<TAB>target_strand<LF>
```

Repetitive-kmer TSV, when provided, has no header and one `lookup_kmer` per
line.

## Runtime Contract

Required arguments:

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

- parse the query/index fixture into fixed-width structs;
- allocate device buffers for query records, index records, output candidates,
  valid flags, and repetitive k-mers;
- launch a CUDA kernel that performs the equality join;
- preserve the query k-mer in the ABI `kmer` field;
- preserve duplicate candidate records;
- fail if requested device allocation exceeds the memory budget;
- report `memory_budget_satisfied`;
- pass `tools/validate_candidate_dump.py`;
- pass `tools/diff_candidate_dumps.py` against the host oracle and expected
  fixture.

## Non-Goals

M1g does not:

- parse FASTQ/FASTA reads;
- compute device-side 2-bit k-mer encoding;
- compute device-side standard form;
- build or upload Flye's full `VertexIndex`;
- replace the Flye backend stub;
- claim performance improvement.

The only correctness claim is that a CUDA kernel can generate ABI-valid
candidate records for a bounded equality-join fixture.
