package arena

import "base:builtin"
import "base:runtime"
import "core:math/rand"
import "core:testing"
import "core:thread"

@(test)
test_alloc_at :: proc(t: ^testing.T) {
	a: Arena(int)
	init(&a, 16)
	defer destroy(&a)
	c: Cache
	defer cache_destroy(&c)

	i, ok := alloc(&a, &c, 42)
	testing.expect(t, ok)
	testing.expect(t, at(&a, i)^ == 42)

	at(&a, i)^ = 99
	testing.expect(t, at(&a, i)^ == 99)
}

@(test)
test_free_reuses_slots :: proc(t: ^testing.T) {
	a: Arena(int)
	init(&a, 16)
	defer destroy(&a)
	c: Cache
	defer cache_destroy(&c)

	i0, _ := alloc(&a, &c, 1)
	i1, _ := alloc(&a, &c, 2)
	testing.expect(t, high_water(&a) == 2)

	free(&a, &c, i1)
	free(&a, &c, i0)

	j0, _ := alloc(&a, &c, 3)
	j1, _ := alloc(&a, &c, 4)
	testing.expectf(t, high_water(&a) == 2, "reuse should not bump: hw=%d", high_water(&a))
	testing.expect(t, j0 == i0 && j1 == i1)
}

@(test)
test_full :: proc(t: ^testing.T) {
	CAP :: 8
	a: Arena(int)
	init(&a, CAP)
	defer destroy(&a)
	c: Cache
	defer cache_destroy(&c)

	for i in 0 ..< CAP {
		_, ok := alloc(&a, &c, i)
		testing.expect(t, ok)
	}
	_, ok := alloc(&a, &c, 999)
	testing.expect(t, !ok)
}

@(private = "file")
NUM_THREADS :: 8
@(private = "file")
STEPS :: 20_000

@(private = "file")
Worker :: struct {
	a:    ^Arena(int),
	id:   int,
	torn: int,
}

@(private = "file")
churn :: proc(w: ^Worker) {
	c: Cache
	defer cache_destroy(&c)

	live: [dynamic][2]int // {index, value}
	defer delete(live)

	state := rand.create(u64(w.id) * 0x9E3779B97F4A7C15 + 1)
	gen := runtime.default_random_generator(&state)

	tag := w.id << 40
	seq := 0
	for step in 0 ..< STEPS {
		if builtin.len(live) == 0 || rand.int_max(2, gen) == 0 {
			val := tag | seq
			seq += 1
			if idx, ok := alloc(w.a, &c, val); ok do append(&live, [2]int{idx, val})
		} else {
			k := rand.int_max(builtin.len(live), gen)
			free(w.a, &c, live[k][0])
			unordered_remove(&live, k)
		}

		// every live slot this worker owns must still read back its own value;
		// a mismatch means another worker was handed the same live index.
		if step % 256 == 0 {
			for e in live {
				if at(w.a, e[0])^ != e[1] do w.torn += 1
			}
		}
	}
}

@(test)
test_concurrent_no_shared_live_index :: proc(t: ^testing.T) {
	a: Arena(int)
	init(&a, 1 << 20)
	defer destroy(&a)

	workers: [NUM_THREADS]Worker
	threads: [NUM_THREADS]^thread.Thread
	for &w, i in workers {
		w = Worker{&a, i, 0}
		threads[i] = thread.create_and_start_with_poly_data(&w, churn)
	}
	for th in threads do thread.join(th)
	for th in threads do thread.destroy(th)

	total_torn := 0
	for w in workers do total_torn += w.torn
	testing.expectf(t, total_torn == 0, "%d torn reads: a live index was shared across workers", total_torn)
}
