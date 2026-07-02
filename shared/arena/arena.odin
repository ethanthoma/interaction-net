package arena

import "base:builtin"
import "base:runtime"
import "core:mem"
import "core:sync"

CACHE_LINE_SIZE :: 64

// Fresh slots are handed out in per-owner chunks of this many slots, so each
// owner's allocations land in a private region instead of interleaving with
// other owners' at a shared frontier (which false-shares lines and defeats the
// L2 spatial prefetcher).
CHUNK_SLOTS :: 4096

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

// Per-owner free list plus the owner's current chunk of fresh slots. Each Cache
// is touched by exactly one thread, so nothing here needs synchronization; only
// chunk refills touch the shared bump.
Cache :: struct {
	_free: [dynamic]int,
	_next: int,
	_end:  int,
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

// Slots reserved so far (chunk tails count as reserved even if never written).
high_water :: proc "contextless" (a: ^$A/Arena($T, $ALIGN)) -> int {
	return sync.atomic_load(&a._bump)
}

@(private = "file")
chunk_refill :: proc(a: ^$A/Arena($T, $ALIGN), want: int) -> (base, end: int, ok: bool) {
	for {
		base = sync.atomic_load(&a._bump)
		if base + want > builtin.len(a._slots) do return 0, 0, false
		_, swapped := sync.atomic_compare_exchange_strong(&a._bump, base, base + want)
		if swapped do return base, base + want, true
	}
}

alloc :: proc(a: ^$A/Arena($T, $ALIGN), cache: ^Cache, value: T) -> (index: int, ok: bool) #no_bounds_check {
	if builtin.len(cache._free) > 0 {
		index = pop(&cache._free)
	} else {
		if cache._next >= cache._end {
			chunk := min(CHUNK_SLOTS, builtin.len(a._slots) - sync.atomic_load(&a._bump))
			if chunk <= 0 do return 0, false
			cache._next, cache._end = chunk_refill(a, chunk) or_return
		}
		index = cache._next
		cache._next += 1
	}
	a._slots[index].value = value
	return index, true
}

free :: proc(a: ^$A/Arena($T, $ALIGN), cache: ^Cache, index: int) {
	append(&cache._free, index)
}

// Reserve count contiguous slots from the owner's chunk (refilling it if the
// remainder is too small; the abandoned tail is bounded waste). Ranges bypass
// the free list: freed slots are reused individually via alloc, never re-formed
// into ranges, so the shared bump grows monotonically with total range volume.
alloc_range :: proc(a: ^$A/Arena($T, $ALIGN), cache: ^Cache, count: int) -> (base: int, ok: bool) {
	if count > cache._end - cache._next {
		want := max(CHUNK_SLOTS, count)
		remaining := builtin.len(a._slots) - sync.atomic_load(&a._bump)
		if want > remaining do want = count
		if want > remaining do return 0, false
		cache._next, cache._end = chunk_refill(a, want) or_return
	}
	base = cache._next
	cache._next += count
	return base, true
}

// Reserve count slots straight from the shared bump, bypassing any Cache and
// its chunking. For one-off setup allocations that must land at the lowest
// free address, not for hot paths.
reserve :: proc(a: ^$A/Arena($T, $ALIGN), count: int) -> (base: int, ok: bool) {
	base = sync.atomic_add(&a._bump, count)
	if base + count > builtin.len(a._slots) do return 0, false
	return base, true
}

at :: proc "contextless" (a: ^$A/Arena($T, $ALIGN), index: int) -> ^T #no_bounds_check {
	return &a._slots[index].value
}
