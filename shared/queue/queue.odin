package queue

import "base:builtin"
import "base:runtime"
import "core:sync"
import "core:thread"

@(private)
Slot :: struct($T: typeid) #align (CACHE_LINE_SIZE) {
	turn: int,
	elem: T,
}

Queue :: struct($T: typeid) {
	_allocator:  runtime.Allocator,
	_slots:      []Slot(T),
	_mask:       int,
	_pad0:       [CACHE_LINE_SIZE]u8,
	_index_head: int,
	_pad1:       [CACHE_LINE_SIZE]u8,
	_index_tail: int,
}

CACHE_LINE_SIZE :: 64

init :: proc(
	q: ^$Q/Queue($T),
	$capacity: int,
	allocator := context.allocator,
) -> runtime.Allocator_Error where capacity >=
	2,
	(capacity & (capacity - 1)) ==
	0 {
	q._allocator = allocator
	q._index_head = 0
	q._index_tail = 0

	q._slots = make([]Slot(T), capacity, allocator) or_return
	for &slot, turn in q._slots {
		slot.turn = turn
	}

	q._mask = capacity - 1

	return nil
}

destroy :: proc(q: ^$Q/Queue($T)) {
	runtime.delete(q._slots, allocator = q._allocator)
}

len :: proc "contextless" (q: ^$Q/Queue($T)) -> int {
	index_head := sync.atomic_load(&q._index_head)
	index_tail := sync.atomic_load(&q._index_tail)
	return index_head - index_tail
}

cap :: proc "contextless" (q: ^$Q/Queue($T)) -> int {
	return builtin.len(q._slots)
}

@(optimization_mode = "favor_size")
push :: proc(q: ^$Q/Queue($T), elem: T) -> (ok: bool = true) #no_bounds_check {
	slot: ^Slot(T)
	index_head := sync.atomic_load_explicit(&q._index_head, .Relaxed)

	for {
		slot = &q._slots[index_head & q._mask]
		turn := sync.atomic_load_explicit(&slot.turn, .Acquire)
		diff := turn - index_head

		if diff == 0 {
			if _, ok = sync.atomic_compare_exchange_weak_explicit(
				&q._index_head,
				index_head,
				index_head + 1,
				.Relaxed,
				.Relaxed,
			); ok {
				break
			}
		} else if diff < 0 {
			return false
		} else {
			index_head = sync.atomic_load_explicit(&q._index_head, .Relaxed)
			thread.yield()
		}
	}

	slot.elem = elem
	sync.atomic_store_explicit(&slot.turn, index_head + 1, .Release)

	return true
}

@(optimization_mode = "favor_size")
pop :: proc(q: ^$Q/Queue($T)) -> (elem: T, ok: bool = true) #no_bounds_check {
	slot: ^Slot(T)
	index_tail := sync.atomic_load_explicit(&q._index_tail, .Relaxed)

	for {
		slot = &q._slots[index_tail & q._mask]
		turn := sync.atomic_load_explicit(&slot.turn, .Acquire)
		diff := turn - index_tail - 1

		if diff == 0 {
			if _, ok = sync.atomic_compare_exchange_weak_explicit(
				&q._index_tail,
				index_tail,
				index_tail + 1,
				.Relaxed,
				.Relaxed,
			); ok {
				break
			}
		} else if diff < 0 {
			return elem, false
		} else {
			index_tail = sync.atomic_load_explicit(&q._index_tail, .Relaxed)
			thread.yield()
		}
	}

	elem = slot.elem
	sync.atomic_store_explicit(&slot.turn, index_tail + q._mask + 1, .Release)
	return elem, true
}

@(optimization_mode = "favor_size")
get :: proc(q: ^$Q/Queue($T), index: int) -> (elem: T, ok: bool = true) #no_bounds_check #optional_ok {
	slot: ^Slot(T)
	index_tail := sync.atomic_load_explicit(&q._index_tail, .Relaxed) + index

	for {
		slot = &q._slots[(index_tail) & q._mask]
		turn := sync.atomic_load_explicit(&slot.turn, .Acquire)
		diff := turn - index_tail - 1

		if diff == 0 {
			break
		} else if diff < 0 {
			return elem, false
		} else {
			index_tail = sync.atomic_load_explicit(&q._index_tail, .Relaxed) + index
			thread.yield()
		}
	}

	elem = slot.elem
	return elem, true
}
