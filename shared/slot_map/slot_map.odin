package slot_map

import "base:builtin"
import "base:runtime"
import "core:mem"
import "core:sync"
import "shared:queue"

CACHE_LINE_SIZE :: 64

Slot_Map :: struct($T: typeid) {
	entries:    []Entry(T),
	free_list:  queue.Queue(int),
	len:        int,
	_allocator: mem.Allocator,
}

Entry :: struct($T: typeid) #align (CACHE_LINE_SIZE) {
	generation: int,
	value:      T,
}

Key :: struct {
	index:      int,
	generation: int,
}

init :: proc(
	sm: ^$S/Slot_Map($T),
	$capacity: int,
	allocator := context.allocator,
) -> runtime.Allocator_Error {
	sm.entries = make([]Entry(T), capacity, allocator) or_return
	queue.init(&sm.free_list, capacity, allocator) or_return
	sm._allocator = allocator

	for i in 0 ..< capacity do queue.push(&sm.free_list, i)
	sync.atomic_store(&sm.len, 0)

	return nil
}

destroy :: proc(sm: ^$S/Slot_Map($T)) {
	delete(sm.entries, sm._allocator)
	queue.destroy(&sm.free_list)
}

len :: proc(sm: ^$S/Slot_Map($T)) -> int {
	return sync.atomic_load(&sm.len)
}

insert :: proc(sm: ^$S/Slot_Map($T), value: T) -> (key: Key, ok: bool) {
	index := queue.pop(&sm.free_list) or_return

	generation := sync.atomic_load(&sm.entries[index].generation)
	sm.entries[index].value = value
	sync.atomic_add(&sm.len, 1)

	return Key{index, generation}, true
}

remove :: proc(sm: ^$S/Slot_Map($T), key: Key) -> Maybe(T) {
	if key.index < 0 || key.index >= builtin.len(sm.entries) do return nil

	if _, won := sync.atomic_compare_exchange_strong(
		&sm.entries[key.index].generation,
		key.generation,
		key.generation + 1,
	); !won {
		return nil
	}

	value := sm.entries[key.index].value
	sync.atomic_add(&sm.len, -1)
	queue.push(&sm.free_list, key.index)

	return value
}

get :: proc(sm: ^$S/Slot_Map($T), key: Key) -> Maybe(T) {
	if key.index < 0 || key.index >= builtin.len(sm.entries) do return nil

	entry := &sm.entries[key.index]
	if sync.atomic_load(&entry.generation) != key.generation do return nil
	value := entry.value
	if sync.atomic_load(&entry.generation) != key.generation do return nil

	return value
}

contains_key :: proc(sm: ^$S/Slot_Map($T), key: Key) -> bool {
	if key.index < 0 || key.index >= builtin.len(sm.entries) do return false
	return sync.atomic_load(&sm.entries[key.index].generation) == key.generation
}

at :: proc(sm: ^$S/Slot_Map($T), index: int) -> ^T {
	return &sm.entries[index].value
}

free_at :: proc(sm: ^$S/Slot_Map($T), index: int) -> bool {
	g := sync.atomic_load(&sm.entries[index].generation)
	if _, won := sync.atomic_compare_exchange_strong(&sm.entries[index].generation, g, g + 1);
	   !won {
		return false
	}

	sync.atomic_add(&sm.len, -1)
	queue.push(&sm.free_list, index)

	return true
}
