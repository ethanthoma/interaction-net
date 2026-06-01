package deque

import "base:builtin"
import "base:runtime"
import "core:sync"

CACHE_LINE_SIZE :: 64

Deque :: struct($T: typeid) {
	_allocator: runtime.Allocator,
	_buffer:    []T,
	_mask:      int,
	_pad0:      [CACHE_LINE_SIZE]u8,
	_top:       int,
	_pad1:      [CACHE_LINE_SIZE]u8,
	_bottom:    int,
}

init :: proc(
	d: ^$D/Deque($T),
	$capacity: int,
	allocator := context.allocator,
) -> runtime.Allocator_Error where capacity >=
	2,
	(capacity & (capacity - 1)) ==
	0 {
	d._allocator = allocator
	d._buffer = make([]T, capacity, allocator) or_return
	d._mask = capacity - 1
	sync.atomic_store(&d._top, 0)
	sync.atomic_store(&d._bottom, 0)
	return nil
}

destroy :: proc(d: ^$D/Deque($T)) {
	delete(d._buffer, d._allocator)
}

len :: proc "contextless" (d: ^$D/Deque($T)) -> int {
	b := sync.atomic_load_explicit(&d._bottom, .Relaxed)
	t := sync.atomic_load_explicit(&d._top, .Relaxed)
	return max(b - t, 0)
}

cap :: proc "contextless" (d: ^$D/Deque($T)) -> int {
	return builtin.len(d._buffer)
}

push :: proc "contextless" (d: ^$D/Deque($T), elem: T) -> (ok: bool) #no_bounds_check {
	b := sync.atomic_load_explicit(&d._bottom, .Relaxed)
	t := sync.atomic_load_explicit(&d._top, .Acquire)
	if b - t >= builtin.len(d._buffer) do return false

	d._buffer[b & d._mask] = elem
	sync.atomic_store_explicit(&d._bottom, b + 1, .Release)
	return true
}

pop :: proc "contextless" (d: ^$D/Deque($T)) -> (elem: T, ok: bool) #no_bounds_check {
	b := sync.atomic_load_explicit(&d._bottom, .Relaxed) - 1
	sync.atomic_store_explicit(&d._bottom, b, .Relaxed)
	sync.atomic_thread_fence(.Seq_Cst)
	t := sync.atomic_load_explicit(&d._top, .Relaxed)

	if t > b {
		sync.atomic_store_explicit(&d._bottom, b + 1, .Relaxed)
		return {}, false
	}

	elem = d._buffer[b & d._mask]
	if t < b do return elem, true

	_, won := sync.atomic_compare_exchange_strong_explicit(&d._top, t, t + 1, .Seq_Cst, .Relaxed)
	sync.atomic_store_explicit(&d._bottom, b + 1, .Relaxed)
	if !won do return {}, false
	return elem, true
}

steal :: proc "contextless" (d: ^$D/Deque($T)) -> (elem: T, ok: bool) #no_bounds_check {
	t := sync.atomic_load_explicit(&d._top, .Acquire)
	if t >= sync.atomic_load_explicit(&d._bottom, .Relaxed) do return {}, false

	sync.atomic_thread_fence(.Seq_Cst)
	b := sync.atomic_load_explicit(&d._bottom, .Acquire)
	if t >= b do return {}, false

	elem = d._buffer[t & d._mask]
	if _, won := sync.atomic_compare_exchange_strong_explicit(
		&d._top,
		t,
		t + 1,
		.Seq_Cst,
		.Relaxed,
	); !won {
		return {}, false
	}
	return elem, true
}
