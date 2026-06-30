# cuFlye CUDA Read Window Smoke Prototype v0

Status: active

Introduced: M1i

Scope: standalone CUDA kernel that slides windows across packed read
sequences, computes Flye-style k-mers and standard-form lookup keys, and
generates a candidate-record-v1 TSV against a flattened index fixture.

## Purpose

M1i moves one step beyond M1h. Instead of supplying one DNA k-mer string per
query row, the fixture supplies short read sequences. CUDA computes the query
k-mer stream by sliding a window across those reads, matching the core behavior
of Flye's `IterKmers` at a bounded fixture scale.

It remains standalone and does not replace the Flye backend stub.

## Runtime Contract

Required arguments:

- `--kmer-size N`, supported range `1..32`;
- `--reads-tsv PATH`;
- `--index-tsv PATH`;
- `--output-tsv PATH`.

Optional arguments:

- `--repetitive-kmers-tsv PATH`;
- `--cpu-output-tsv PATH`: write a host oracle generated from the same fixture;
- `--device N`: CUDA device id, default from `CUFLYE_CUDA_DEVICE` or `0`;
- `--memory-budget-bytes N`: maximum allowed device allocation;
- `--json-output PATH`: compact runtime manifest.

The prototype must:

- parse packed read sequences into read metadata plus a flat base buffer;
- compute query windows on device;
- compute forward k-mer representation, reverse complement, and standard form
  on device;
- preserve the forward query representation in ABI field `kmer`;
- skip repetitive standard-form lookup keys;
- skip trivial same-read/same-position hits;
- preserve duplicate candidate records;
- pass `tools/validate_candidate_dump.py`;
- pass `tools/diff_candidate_dumps.py` against the host oracle and expected
  fixture.

## Non-Goals

M1i does not:

- parse FASTQ/FASTA files;
- build or upload Flye's full `VertexIndex`;
- transform reverse-complement target coordinates during index construction;
- replace the Flye backend stub;
- claim performance improvement.

## M2c Extension

M2c removes the original fixed `MAX_READ_SIZE=256` read storage limit. The
backend still accepts the same `reads.tsv` format, but internally uploads:

- `QueryReadMeta[]`: query id, read length, and sequence offset;
- `char[]`: concatenated read bases.

Runtime JSON includes:

- `dynamic_read_bases: true`;
- `read_base_bytes`;
- `max_read_length`;
- `read_meta_record_size_bytes`.

The host CPU oracle is generated only when `--cpu-output-tsv` is supplied. This
keeps proof runs able to compare CPU/GPU output while avoiding hidden CPU oracle
work when Flye invokes the external CUDA backend.

The correctness claim after M2c is that CUDA device code can perform
read-window generation on both bounded fixtures and one real `pack-dump-v0`
query bundle before candidate equality join.
