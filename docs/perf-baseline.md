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
at a time so each step is measured in isolation.

Measured finding: packing `nums` (16x) and `nodes` (8x) is throughput-neutral —
the working sets already fit in cache, so arena footprint is NOT the throughput
bottleneck. These are memory wins (reserve ~800 MB → ~85 MB). The real ceiling is
parallel scaling.

## parallel scaling (2026-07-02, 24-core box)

`INIO_WORKERS=N` overrides the worker count (defaults to core count). MIps by N,
median of 3:

| workers | rec.inio | stress.inio |
| ------- | -------- | ----------- |
| 1       | 1.19     | 1.16        |
| 2       | 2.68     | 1.89 (peak) |
| 4       | 3.00 (peak) | 1.63     |
| 8       | 2.65     | 1.69        |
| 16      | 2.60     | 1.59        |
| 24      | 2.53     | 1.50        |

The runtime peaks at 2-4 workers (~2.5x) then REGRESSES as cores are added —
using all 24 cores is slower than using 2. This is the goal-1 bottleneck:
HVM-class runtimes scale near-linearly. Coordination overhead dominates past 4
cores.

Confirmed via `Work` counters (`-define:PROFILE=true`, take_work outcome mix):

| workers | own | steal | global | miss (spin) |
| ------- | --- | ----- | ------ | ----------- |
| 1       | 100%| 0%    | 0%     | 0%          |
| 4       | 32% | 18%   | 0%     | 50%         |
| 24      | 17% | 15%   | 0%     | 68%         |

The miss ratio climbs with core count (0 → 50 → 68%): at 24 workers ~5M of ~7.3M
take_work calls find no work and fall into backoff, and EVERY miss does
`atomic_load(&outstanding)` on the shared line — 5M contended loads that grow with
worker count and fight the active workers' add/sub. That is the anti-scaling
mechanism. Steal is 15-18% (real parallelism exists, just not enough to feed 24
cores), and the global queue is unused (0%, overflow 0) — so the MPMC queue is NOT
the problem; the single `outstanding` counter is, and the per-miss load dominates
its add/sub traffic.

Fix landed: only load `outstanding` in the deep-idle path, not on every busy-spin
(`outstanding == 0` is a stable terminal state, reachable only once all workers
are quiescent, so busy-spinning workers never need to check it). Interleaved A/B
on rec: +8.3% at 24 workers (2.57 → 2.78 MIps), +4.5% at 4 workers — larger where
more idle workers were spinning, as predicted. It does not cure the anti-scaling
(rec still peaks at 4 workers): what remains is the per-redex `atomic_add`/`sub`
on `outstanding` (2 per interaction, still contended) and rec's structural
parallelism deficit (68% miss — not enough independent redexes to feed 24 cores).

## parallel workload scaling (fork.inio, 2026-07-02)

rec/stress are LINEAR recursions (each level spawns one recursive call), so they
cannot feed 24 cores — their anti-scaling is a workload property. `fork.inio` is
a binary fork/join (`fork(n) = fork(n-1) + fork(n-1)`, 2^12 independent
`sum(100)` leaves) and tells the opposite story:

| workers | MIps | speedup |
| ------- | ---- | ------- |
| 1       | 1.22 | 1.0x    |
| 2       | 3.23 | 2.7x    |
| 4       | 6.54 | 5.4x    |
| 8       | 10.4 | 8.5x    |
| 16      | 14.5 | 11.9x   |
| 24      | 17.2 | 14.2x   |

take_work mix at 24 workers: own 96.0%, steal 3.6%, global 0%, miss 0.3% (vs
rec's 68% miss). The scheduler is validated: with parallel work it scales
near-linearly to 8 workers and monotonically to 24 (59% efficiency), 17-21 MIps
sustained. The superlinear 2-4w region is unexplained (cache effects?) but
consistent across runs.

Conclusions:
- The work-stealing coordination is NOT the goal-1 blocker. Single-worker
  per-interaction cost (~1.2 MIps sequential) and workload parallelism are.
- The `outstanding` add/sub per redex did not stop 14x scaling; removing it via
  quiescence termination detection is now a marginal lever, not a priority.
- rec/stress anti-scaling is inherent to linear recursion + idle spinning; the
  deep-idle termination check (below) already softened it. A worker-count
  heuristic (don't spawn 24 workers for sequential workloads) would close the
  rest, but is polish, not architecture.

## per-interaction cost (2026-07-02)

Single-worker fork.inio via `perf stat`: ~4,700 instructions per interaction
(15.8B instructions / 3.38M interactions), IPC 2.3, 0.16 cache-misses per
interaction. The CPU is not stalled — the runtime simply executes 20-80x more
instructions per interaction than an HVM-class runtime (~50-200). Closing that
is a constant-factor redesign (port decoding, link/substitution machinery,
dispatch), not a cache or scheduling problem. ~12% of cycles are kernel page
faults from lazily faulting the 1 GB padded vars arena (16M x 64B slots).

RESOLVED (2026-07-02): the constant factor was Odin's `bit_field` lowering — see
"hot loop redesign" below. Post-fix cost is ~330 instructions/interaction.

Measured micro-experiments, so nobody re-runs them expecting wins:

- Contiguous def instantiation (LANDED): `arena.alloc_range` reserves per-def
  node/var/num ranges with one atomic bump; remap = base offset added to the
  packed addr bits; the three per-call `make`/`delete` maps are gone.
  -6.5% instructions, +2-3% single-worker MIps (consistent), neutral at 24w.
- Replacing `get_data` union decoding with inlined bit-field accessors:
  REGRESSED (+10% instructions, -7% MIps). The shared out-of-line decode is
  better codegen than 37 inlined copies. Reverted.
- Per-worker scratch buffers for the call() maps (keeping per-item allocs):
  wash at 1w, -10% at 24w. Superseded by contiguous ranges. Reverted.

Measurement caveat: perf symbol shares on these Odin binaries are unreliable —
`@(private)` procs inlined by `-o:speed` emit no symbols, so samples get
attributed to the nearest preceding named symbol (e.g. a ~10-instruction
`adjust_addr` "showing" 22%). Trust `perf stat` instruction/cycle totals,
interleaved A/B wall-clock, and interaction counts; do not trust per-symbol
percentages without disassembly-level confirmation. For real attribution, build
with `-o:speed -debug` (identical codegen, adds DWARF) and use
`perf report -s srcline`, which resolves through inlining.

## hot loop redesign (2026-07-02)

`perf report -s srcline` on a `-debug` build attributed ~49% of ALL instructions
to `base:runtime/internal.odin` `__read_bits`/`__write_bits` — Odin lowers
access to non-byte-aligned `bit_field` fields through helpers that loop ONE BIT
AT A TIME. `Port` was `bit_field u32 { tag: 3 bits, data: 29 bits }`, so `data`
(and every `Num_Data`/`Op_Data` field) paid a ~29-iteration loop per read and
write, on every port touched by every rule. This retroactively explains the two
"reverted micro-experiments" above: inlining accessors ADDED bit_field accesses
(hence +10% instructions), and adjust_addr's 22% perf share was largely real.

Fix: `Port` is a `distinct u32`; tag/payload/type/addr access is explicit
shift/mask in `#force_inline` accessors (`net.odin`), same bit layout. Results
byte-identical on all examples.

- instructions/interaction: 4,678 -> 330 (14x)
- fork 1w: 1.23 -> 2.44 MIps; rec 1w: 1.17 -> 2.42 (2x)
- rec 24w: 2.70 -> 4.45 (+65%)
- fork 24w REGRESSED: 16.9 -> 14.2, unstable — compute got so cheap that the
  run became page-fault-bound (sys 0.79s -> 4.10s, faults 229k -> 444k; 74% of
  task-clock in the kernel faulting the 1 GB padded vars arena).

Packing the vars arena (64B -> 4B slots, the "risky" lever 3 below) fixed that
and measured as a pure win — the feared `vars_exchange` false sharing never
showed: fork 24w 14.2 -> 23.2 (stable), fork 1w +5%, rec 1w +3%, rec 24w wash.
Vars reserve is now 64 MB (was 1 GB).

Net vs the pre-redesign baseline: fork 1w +108%, rec 1w +114%, fork 24w +37%,
rec 24w +65%. Remaining hot-loop instruction budget (~330/interaction) by
srcline: alloc/free free-list traffic, link/enter atomic exchanges, deque and
`outstanding` coordination — plus residual page faults on first-touch of the
packed arenas.

Older notes on the rec/stress anti-scaling investigation:

Older levers, in order:

1. Pack the `nums` arena (align 4B) — DONE. Footprint 8.08 MB → 502 KB peak
   (16x). Throughput on rec is unchanged (packed vs padded A/B: median 2.78 vs
   2.82 MIps — within noise), because the num set was already cache-resident on
   this few-core box. A memory win with no regression; the throughput bottleneck
   is elsewhere.
2. Pack the `nodes` arena (align 8B) — DONE. 8x smaller (reserve 536 MB → 67 MB).
   Throughput on rec unchanged (packed vs padded A/B: median 2.50 vs 2.41 MIps —
   within noise). Nodes are written by their allocating worker and only *read*
   cross-worker, so no false-sharing regression from packing.
3. Pack the `vars` arena — DONE (2026-07-02, as part of the hot loop redesign
   above). The feared `vars_exchange` false sharing did not show in A/B; the
   page-fault relief dominates (fork 24w +63%).
4. Per-worker interaction counter — DONE (removed the one global atomic in
   `interact()`).
5. Inline numbers into the `Port`. Measured 1.32 arena touches + 1.68 alloc/free
   ops per interaction, so not a wash — but it needs a wider u64 `Port`, doubling
   every `Pair` (annihilate pays 2x on 100% of interactions), and packing already
   shrinks the num arena 16x. Re-measure after node packing; the marginal win may
   not clear the u64 cost.
