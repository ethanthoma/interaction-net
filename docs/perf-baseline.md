# Runtime perf baseline

## Reproduce

```sh
# throughput (MIps), release build
odin build src -out:inio -collection:shared=shared -o:speed
./inio run examples/rec.inio

# per-rule interaction breakdown
odin build src -out:inio_p -collection:shared=shared -o:speed -define:PROFILE=true
./inio_p run examples/rec.inio
```

`PROFILE` is a compile-time flag (`#config(PROFILE, false)` in
`src/runtime.odin`); it adds atomic per-rule and per-`nums`-arena counters plus a
peak-footprint report, and compiles to nothing when unset.

## Baseline (2026-06-30)

| example     | interactions | MIps |
| ----------- | ------------ | ---- |
| rec.inio    | 2,345,693    | ~2.7 |
| stress.inio | 32,853       | ~1.7 |

Per-rule share (rec.inio):

| rule               | share      |
| ------------------ | ---------- |
| annihilate         | 31.6%      |
| operate            | 21.1%      |
| erase              | 15.8%      |
| void / call / cond | 10.5% each |
| commute / apply    | 0%         |

stress.inio: annihilate 25%, operate 25%, call/erase/void/cond 12.5% each.

## nums-arena traffic (2026-07-01)

Per-interaction `nums`-arena touches and peak live footprint (physical, since
each `u32` sits in a 64-byte `Slot`):

| example     | touches/int | alloc+free/int | peak values | physical |
| ----------- | ----------- | -------------- | ----------- | -------- |
| rec.inio    | 1.32        | 1.68           | 126,302     | 8.08 MB  |
| stress.inio | 1.50        | 1.00           | 4,348       | 278 KB   |

The reads are real, but the allocation churn is the surprise: alloc ≈ free ≈
interactions, so on average every interaction does one num alloc and one num free
(free-list push/pop). The peak footprint is not cache-resident — but that is the
64-byte `Slot` padding, not the boxing: packed to 4 bytes, rec's num set is
~505 KB and stress's is ~17 KB (L1).

The hot path is annihilate + operate. HVM-class CPU throughput is 2-3 orders of
magnitude above this baseline, so the gap is architectural. Levers, in order:

1. Drop the 64-byte `Slot` cache-line padding (`shared/arena/arena.odin`). It is
   the dominant memory problem and hits *every* arena: an 8-byte `Pair` and a
   4-byte num each burn a full line (8x / 16x blowup) — it alone makes rec's num
   set 8 MB. Needs per-worker packed arena segments to stay false-sharing free.
2. Per-worker interaction counter — DONE. Was a single global atomic in
   `interact()` ping-ponging one line across all workers every interaction.
3. Inline numbers into the `Port`. Measured 1.32 arena touches + 1.68 alloc/free
   ops per interaction, so not a wash — but it needs a wider u64 `Port`, doubling
   every `Pair` (annihilate, 32%, pays 2x on 100% of interactions), and packing
   (#1) already shrinks the num arena 16x. Re-measure after packing; the marginal
   win may not clear the u64 cost.
