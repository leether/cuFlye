# cuFlye CUDA Read Window Smoke Prototype v0

Status: active

Introduced: M1i

Scope: standalone CUDA kernel that slides fixed-size windows across bounded read
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

- parse bounded read sequences into fixed-width structs;
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

The only correctness claim is that CUDA device code can perform bounded
read-window generation before candidate equality join.
