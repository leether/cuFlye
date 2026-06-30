# cuFlye Read Alignment Replay Fixture v0

Status: accepted

Introduced: M5b

Scope: a single selected positive read inside Flye `ReadAligner::alignReads`.

## Purpose

`cuflye-read-alignment-replay-fixture-v0` captures enough bounded CPU state to
replay `ReadAligner::chainReadAlignments` outside a full Flye run. It is the
bridge between the M5a full read-alignment oracle and a future CUDA
read-to-graph chain kernel.

## Files

| File | Meaning |
| --- | --- |
| `manifest.json` | Fixture schema, selected query id, counts, and chaining parameters. |
| `read.tsv` | Selected read id and sequence. |
| `edge-sequences.tsv` | Edge-sequence id and sequence for edge overlaps in the fixture. |
| `edge-overlaps.tsv` | Candidate edge alignments fed into `chainReadAlignments`. |
| `chain-divergence.tsv` | Divergence and accepted flag for each candidate chain. |
| `oracle.read-alignment.tsv` | Accepted chain oracle in `read-alignment-v1` format. |

## Edge-Overlap TSV

`edge-overlaps.tsv` has 14 tab-separated fields:

```text
candidate_id<TAB>read_id<TAB>read_begin<TAB>read_end<TAB>read_len<TAB>edge_id<TAB>edge_left_node<TAB>edge_right_node<TAB>edge_seq_id<TAB>edge_begin<TAB>edge_end<TAB>edge_len<TAB>score<TAB>seq_divergence
```

`edge_left_node` and `edge_right_node` are required because Flye extends a chain
only when the previous edge's right node equals the next edge's left node.

## Replay Contract

A replay implementation must:

- sort edge-overlap rows by `read_begin`;
- run the same active/frozen chain DP as `ReadAligner::chainReadAlignments`;
- use `chain-divergence.tsv` to apply Flye's divergence acceptance decision;
- emit accepted chains as `read-alignment-v1`;
- canonical-diff the replay output against `oracle.read-alignment.tsv`.

The fixture intentionally stores chain divergence values instead of requiring
the replay tool to reimplement Flye's optional edlib base realignment.

## Deterministic Mode

Fixture dump requires `--threads 1` and a positive
`CUFLYE_READ_ALIGNMENT_REPLAY_QUERY_ID`. The dump fails closed otherwise.

M5e adds multi-query fixture harvest with
`CUFLYE_READ_ALIGNMENT_REPLAY_QUERY_IDS`, a comma-separated list of positive
read ids. When this variable is set, the dump root contains one fixture
directory per selected read:

```text
<dump-root>/
  query_200/
    manifest.json
    read.tsv
    edge-sequences.tsv
    edge-overlaps.tsv
    chain-divergence.tsv
    oracle.read-alignment.tsv
  query_201/
    ...
```

`CUFLYE_READ_ALIGNMENT_REPLAY_QUERY_IDS` fails closed on empty list elements,
non-decimal values, or non-positive ids. The single-query
`CUFLYE_READ_ALIGNMENT_REPLAY_QUERY_ID` mode keeps the original flat fixture
directory layout for compatibility with M5b-M5d proofs.
