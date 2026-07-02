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
magnitude above this baseline, so the gap is architectural. The 64-byte `Slot`
cache-line padding (`shared/arena/arena.odin`) is the dominant memory waste — it
hits *every* arena (an 8-byte `Pair` and a 4-byte num each burn a full line, 8x /
16x blowup). Slot alignment is now a per-arena type parameter, packed one arena
at a time so each step is measured in isolation. Levers, in order:

1. Pack the `nums` arena (align 4B) — DONE. Footprint 8.08 MB → 502 KB peak
   (16x). Throughput on rec is unchanged (packed vs padded A/B: median 2.78 vs
   2.82 MIps — within noise), because the num set was already cache-resident on
   this few-core box. A memory win with no regression; the throughput bottleneck
   is elsewhere.
2. Pack the `nodes` arena (align 8B) — NEXT. This is the hot one: annihilate is
   32% of interactions and reads/writes node `Pair`s. Nodes are written by their
   allocating worker (alloc + call-expansion) and only *read* cross-worker, so
   per-worker alloc slabs are not required to stay false-sharing free — but
   cross-worker frees (a stolen redex freeing another worker's node) reuse a slot
   in a peer's region; watch for a throughput regression in the A/B.
3. Pack the `vars` arena — RISKY, deferred. Vars are written in place by any
   worker via `sync.atomic_exchange` (the substitution linker, `vars_exchange`),
   so tight-packing puts independent vars on a shared line and false-shares the
   hottest concurrent write. The 64-byte padding is load-bearing here; only pack
   behind a measured before/after.
4. Per-worker interaction counter — DONE (removed the one global atomic in
   `interact()`).
5. Inline numbers into the `Port`. Measured 1.32 arena touches + 1.68 alloc/free
   ops per interaction, so not a wash — but it needs a wider u64 `Port`, doubling
   every `Pair` (annihilate pays 2x on 100% of interactions), and packing already
   shrinks the num arena 16x. Re-measure after node packing; the marginal win may
   not clear the u64 cost.
