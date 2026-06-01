package deque

import "core:sync"
import "core:testing"
import "core:thread"

@(test)
test_push_pop_lifo :: proc(t: ^testing.T) {
	d: Deque(int)
	init(&d, 16)
	defer destroy(&d)

	for i in 0 ..< 5 do testing.expect(t, push(&d, i))
	testing.expect(t, len(&d) == 5)

	for want := 4; want >= 0; want -= 1 {
		e, ok := pop(&d)
		testing.expect(t, ok)
		testing.expectf(t, e == want, "pop = %d, want %d", e, want)
	}

	_, ok := pop(&d)
	testing.expect(t, !ok)
	testing.expect(t, len(&d) == 0)
}

@(test)
test_steal_fifo :: proc(t: ^testing.T) {
	d: Deque(int)
	init(&d, 16)
	defer destroy(&d)

	for i in 0 ..< 5 do push(&d, i)

	for want in 0 ..< 5 {
		e, ok := steal(&d)
		testing.expect(t, ok)
		testing.expectf(t, e == want, "steal = %d, want %d", e, want)
	}

	_, ok := steal(&d)
	testing.expect(t, !ok)
}

@(test)
test_full :: proc(t: ^testing.T) {
	CAP :: 8
	d: Deque(int)
	init(&d, CAP)
	defer destroy(&d)

	for i in 0 ..< CAP do testing.expect(t, push(&d, i))
	testing.expect(t, !push(&d, 999))

	e, ok := pop(&d)
	testing.expect(t, ok && e == CAP - 1)
	testing.expect(t, push(&d, 999))
}

@(test)
test_pop_steal_meet :: proc(t: ^testing.T) {
	d: Deque(int)
	init(&d, 16)
	defer destroy(&d)

	push(&d, 10)
	push(&d, 20)

	s, sok := steal(&d)
	testing.expect(t, sok && s == 10)

	p, pok := pop(&d)
	testing.expect(t, pok && p == 20)

	_, ok := pop(&d)
	testing.expect(t, !ok)
	_, ok2 := steal(&d)
	testing.expect(t, !ok2)
}

@(private = "file")
NUM_THIEVES :: 4
@(private = "file")
N :: 100_000

@(private = "file")
Race :: struct {
	d:    Deque(int),
	stop: bool,
	got:  [NUM_THIEVES + 1][dynamic]int,
}

@(private = "file")
owner :: proc(r: ^Race) {
	for i in 0 ..< N {
		for !push(&r.d, i) do thread.yield()
	}
	for {
		e, ok := pop(&r.d)
		if !ok do break
		append(&r.got[0], e)
	}
	sync.atomic_store(&r.stop, true)
}

@(private = "file")
thief :: proc(r: ^Race, id: int) {
	for !sync.atomic_load(&r.stop) {
		if e, ok := steal(&r.d); ok do append(&r.got[id], e)
	}
	for {
		e, ok := steal(&r.d)
		if !ok do break
		append(&r.got[id], e)
	}
}

@(test)
test_concurrent_each_taken_once :: proc(t: ^testing.T) {
	r := new(Race)
	defer free(r)
	init(&r.d, 1 << 17)
	defer destroy(&r.d)
	defer for &g in r.got do delete(g)

	owner_thread := thread.create_and_start_with_poly_data(r, owner)
	thieves: [NUM_THIEVES]^thread.Thread
	for &th, i in thieves do th = thread.create_and_start_with_poly_data2(r, i + 1, thief)

	thread.join(owner_thread)
	for th in thieves do thread.join(th)
	thread.destroy(owner_thread)
	for th in thieves do thread.destroy(th)

	seen := make([]bool, N)
	defer delete(seen)
	count := 0
	for &g in r.got {
		for v in g {
			testing.expectf(t, v >= 0 && v < N, "out-of-range value %d", v)
			testing.expectf(t, !seen[v], "value %d taken more than once", v)
			seen[v] = true
			count += 1
		}
	}
	testing.expectf(t, count == N, "took %d values, want %d", count, N)
}
