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
`src/runtime.odin`); it adds an atomic per-rule counter and an end-of-run
report, and compiles to nothing when unset.

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

The hot path is annihilate + operaten. HVM-class CPU throughput is 2-3 orders of
magnitude above this baseline, so the gap is architectural (probably?).

1. Inline numbers into the `Port` a la operate/cond/void hit the separate `nums`
   arena on ~40% of interactions. Blocked on the 32-bit Port width (25-bit addr
   can't hold a 32-bit value + type) which means it needs a wider Port/Pair
   (should be fine?).
2. Drop the 64-byte `Slot` cache-line padding (`shared/arena/arena.odin`) which
   makes an 8-byte `Pair` occupies a whole line (added for cache contention),
   ~8x memory bandwidth on annihilate. Needs per-worker packed arena segments to
   stay false-sharing free.
3. The single global atomic in `interact()` ping-pongs one cache line across all
   workers on every interaction so we should have a per-worker interaction
   counter.
