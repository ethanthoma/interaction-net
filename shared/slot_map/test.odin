package slot_map

import "base:builtin"
import "base:runtime"
import "core:math/rand"
import "core:testing"
import "core:thread"

@(test)
test_insert_remove :: proc(t: ^testing.T) {
	sm: Slot_Map(int)
	init(&sm, 16)
	defer destroy(&sm)

	k := insert(&sm, 42)
	testing.expect(t, contains_key(&sm, k))
	testing.expect(t, len(&sm) == 1)

	v := remove(&sm, k)
	testing.expect(t, v != nil && v.? == 42)
	testing.expect(t, !contains_key(&sm, k))
	testing.expect(t, len(&sm) == 0)

	testing.expect(t, remove(&sm, k) == nil)
}

@(test)
test_generation_invalidates_key :: proc(t: ^testing.T) {
	sm: Slot_Map(int)
	init(&sm, 16)
	defer destroy(&sm)

	k1 := insert(&sm, 1)
	remove(&sm, k1)
	k2 := insert(&sm, 2)

	testing.expect(t, k1.index == k2.index)
	testing.expect(t, k1.generation != k2.generation)
	testing.expect(t, !contains_key(&sm, k1))
	testing.expect(t, contains_key(&sm, k2))
}

@(test)
test_property_model :: proc(t: ^testing.T) {
	for trial in 0 ..< 200 {
		seed := u64(trial) * 0x9E3779B97F4A7C15 + 1
		state := rand.create(seed)
		gen := runtime.default_random_generator(&state)

		sm: Slot_Map(int)
		init(&sm, 1 << 12)
		defer destroy(&sm)

		model: map[Key]int
		live, dead: [dynamic]Key
		defer delete(model)
		defer delete(live)
		defer delete(dead)

		next := 0
		for step in 0 ..< 600 {
			roll := rand.int_max(100, gen)
			switch {
			case builtin.len(live) == 0 || roll < 50:
				k := insert(&sm, next)
				_, dup := model[k]
				testing.expectf(t, !dup, "seed %d: insert returned live key %v", seed, k)
				model[k] = next
				append(&live, k)
				testing.expect(t, contains_key(&sm, k))
				next += 1
			case roll < 85:
				i := rand.int_max(builtin.len(live), gen)
				k := live[i]
				got := remove(&sm, k)
				testing.expectf(
					t,
					got != nil && got.? == model[k],
					"seed %d: remove(%v) = %v, want %d",
					seed,
					k,
					got,
					model[k],
				)
				delete_key(&model, k)
				unordered_remove(&live, i)
				append(&dead, k)
				testing.expect(t, !contains_key(&sm, k))
			case builtin.len(dead) > 0:
				k := dead[rand.int_max(builtin.len(dead), gen)]
				testing.expectf(t, remove(&sm, k) == nil, "seed %d: stale remove(%v) != nil", seed, k)
				testing.expect(t, !contains_key(&sm, k))
			}

			testing.expectf(
				t,
				len(&sm) == builtin.len(model),
				"seed %d step %d: len %d != model %d",
				seed,
				step,
				len(&sm),
				builtin.len(model),
			)
		}
	}
}

@(private = "file")
Op :: enum u8 {
	Insert,
	Remove_Live,
	Remove_Stale,
}

@(private = "file")
ALL_OPS :: [?]Op{.Insert, .Remove_Live, .Remove_Stale}

@(test)
test_swarm :: proc(t: ^testing.T) {
	for trial in 0 ..< 256 {
		seed := u64(trial) * 0x2545F4914F6CDD1D + 1
		state := rand.create(seed)
		gen := runtime.default_random_generator(&state)

		swarm: [dynamic]Op
		defer delete(swarm)
		append(&swarm, Op.Insert)
		for op in ALL_OPS do if op != .Insert && rand.int_max(2, gen) == 1 do append(&swarm, op)

		sm: Slot_Map(int)
		init(&sm, 1 << 12)
		defer destroy(&sm)

		model: map[Key]int
		live, dead: [dynamic]Key
		defer delete(model)
		defer delete(live)
		defer delete(dead)

		next := 0
		for step in 0 ..< 500 {
			op := swarm[rand.int_max(builtin.len(swarm), gen)]
			if (op == .Remove_Live && builtin.len(live) == 0) ||
			   (op == .Remove_Stale && builtin.len(dead) == 0) {
				op = .Insert
			}

			switch op {
			case .Insert:
				k := insert(&sm, next)
				model[k] = next
				append(&live, k)
				next += 1
			case .Remove_Live:
				i := rand.int_max(builtin.len(live), gen)
				k := live[i]
				testing.expect(t, remove(&sm, k) != nil)
				delete_key(&model, k)
				unordered_remove(&live, i)
				append(&dead, k)
			case .Remove_Stale:
				k := dead[rand.int_max(builtin.len(dead), gen)]
				testing.expect(t, remove(&sm, k) == nil)
			}

			testing.expectf(
				t,
				len(&sm) == builtin.len(model),
				"seed %d: len %d != model %d",
				seed,
				len(&sm),
				builtin.len(model),
			)
		}

		for k in live do testing.expect(t, contains_key(&sm, k))
		for k in dead do testing.expect(t, !contains_key(&sm, k))
	}
}

// known-bug demos, disabled by default; run with -define:SLOTMAP_STRESS=true
@(private = "file")
STRESS :: #config(SLOTMAP_STRESS, false)

@(test)
test_concurrent_insert :: proc(t: ^testing.T) {
	when !STRESS {
		return
	}

	NUM_THREADS :: 8
	PER_THREAD :: 4000

	sm: Slot_Map(int)
	init(&sm, 1 << 16)
	defer destroy(&sm)

	worker :: proc(sm: ^Slot_Map(int), id: int) {
		for i in 0 ..< PER_THREAD do insert(sm, id * PER_THREAD + i)
	}

	threads: [NUM_THREADS]^thread.Thread
	for &th, id in threads do th = thread.create_and_start_with_poly_data2(&sm, id, worker)
	for th in threads do thread.join(th)

	testing.expectf(
		t,
		len(&sm) == NUM_THREADS * PER_THREAD,
		"insert is not thread-safe: len %d != %d",
		len(&sm),
		NUM_THREADS * PER_THREAD,
	)
}

@(test)
test_capacity_overflow :: proc(t: ^testing.T) {
	when !STRESS {
		return
	}

	CAP :: 8
	N :: 4 * CAP

	sm: Slot_Map(int)
	init(&sm, CAP)
	defer destroy(&sm)

	keys: [dynamic]Key
	defer delete(keys)
	for i in 0 ..< N do append(&keys, insert(&sm, i))
	for k in keys do remove(&sm, k)
	clear(&keys)
	for i in 0 ..< N do append(&keys, insert(&sm, 100 + i))

	testing.expectf(
		t,
		builtin.len(sm.entries) == N,
		"free-list slot leak: entries grew to %d, expected %d",
		builtin.len(sm.entries),
		N,
	)
}
