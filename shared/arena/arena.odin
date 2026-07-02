package arena

import "base:builtin"
import "base:runtime"
import "core:mem"
import "core:sync"

CACHE_LINE_SIZE :: 64

// ALIGN is the byte alignment of each slot. Use CACHE_LINE_SIZE to isolate every
// slot on its own line when different threads write neighbouring slots in place;
// use align_of(T) to pack slots tightly and reclaim the wasted bandwidth.
Slot :: struct($T: typeid, $ALIGN: int) #align (ALIGN) {
	value: T,
}

Arena :: struct($T: typeid, $ALIGN: int) {
	_slots:     []Slot(T, ALIGN),
	_bump:      int,
	_allocator: mem.Allocator,
}

// Per-owner free list. Each Cache is touched by exactly one thread, so its
// push/pop need no synchronization; only the fresh-slot bump is atomic.
Cache :: struct {
	_free: [dynamic]int,
}

init :: proc(
	a: ^$A/Arena($T, $ALIGN),
	$capacity: int,
	allocator := context.allocator,
) -> runtime.Allocator_Error {
	a._allocator = allocator
	a._slots = make([]Slot(T, ALIGN), capacity, allocator) or_return
	sync.atomic_store(&a._bump, 0)
	return nil
}

destroy :: proc(a: ^$A/Arena($T, $ALIGN)) {
	delete(a._slots, a._allocator)
}

cache_destroy :: proc(c: ^Cache) {
	delete(c._free)
}

cap :: proc "contextless" (a: ^$A/Arena($T, $ALIGN)) -> int {
	return builtin.len(a._slots)
}

high_water :: proc "contextless" (a: ^$A/Arena($T, $ALIGN)) -> int {
	return sync.atomic_load(&a._bump)
}

alloc :: proc(a: ^$A/Arena($T, $ALIGN), cache: ^Cache, value: T) -> (index: int, ok: bool) #no_bounds_check {
	if builtin.len(cache._free) > 0 {
		index = pop(&cache._free)
	} else {
		index = sync.atomic_add(&a._bump, 1)
		if index >= builtin.len(a._slots) do return 0, false
	}
	a._slots[index].value = value
	return index, true
}

free :: proc(a: ^$A/Arena($T, $ALIGN), cache: ^Cache, index: int) {
	append(&cache._free, index)
}

at :: proc "contextless" (a: ^$A/Arena($T, $ALIGN), index: int) -> ^T #no_bounds_check {
	return &a._slots[index].value
}
