package queue

import "base:runtime"
import "core:sync"
import "core:thread"

Slot :: struct($T: typeid) {
	turn: int,
	elem: T,
}

Queue :: struct($T: typeid) {
	_capacity:   int,
	_allocator:  runtime.Allocator,
	_slots:      []Slot(T),
	_mask:       int,
	_pad0:       [8]u8,
	_index_head: int,
	_pad1:       [8]u8,
	_index_tail: int,
}

init :: proc(q: ^$Q/Queue($T), $capacity: int, allocator := context.allocator) where capacity >= 2,
	(capacity & (capacity - 1)) == 0 {
	q._capacity = capacity
	q._allocator = allocator
	q._index_head = 0
	q._index_tail = 0

	q._slots = make([]Slot(T), capacity, allocator)
	for &slot, turn in q._slots {
		slot.turn = turn
	}

	q._mask = capacity - 1
}

destroy :: proc(q: ^$Q/Queue($T)) {
	delete(q._slots)
}

push :: proc(q: ^$Q/Queue($T), elem: T) -> (ok: bool = true) {
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

pop :: proc(q: ^$Q/Queue($T)) -> (elem: T, ok: bool = true) {
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
