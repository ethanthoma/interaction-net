package slot_map

import "base:builtin"
import "base:runtime"
import "core:math/rand"
import "core:testing"

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
test_swarm :: proc(t: ^testing.T) {
	CAPACITY :: 1 << 13
	OPS :: 4000

	for trial in 0 ..< 32 {
		sm: Slot_Map(int)
		init(&sm, CAPACITY)
		defer destroy(&sm)

		state := rand.create(u64(trial) * 2654435761 + 1)
		gen := runtime.default_random_generator(&state)

		live, dead: [dynamic]Key
		defer delete(live)
		defer delete(dead)

		for op in 0 ..< OPS {
			if builtin.len(live) == 0 || rand.int_max(10, gen) < 6 {
				append(&live, insert(&sm, op))
			} else {
				i := rand.int_max(builtin.len(live), gen)
				testing.expect(t, remove(&sm, live[i]) != nil)
				append(&dead, live[i])
				unordered_remove(&live, i)
			}
		}

		testing.expectf(
			t,
			len(&sm) == builtin.len(live),
			"trial %d: len %d != live %d",
			trial,
			len(&sm),
			builtin.len(live),
		)
		for k in live do testing.expect(t, contains_key(&sm, k))
		for k in dead do testing.expect(t, !contains_key(&sm, k))
	}
}
