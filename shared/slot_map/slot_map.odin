package slot_map

import "base:builtin"
import "base:runtime"
import "core:mem"
import "core:sync"
import "shared:queue"

CACHE_LINE_SIZE :: 64

Slot_Map :: struct($T: typeid) {
	entries:    [dynamic]Entry(T),
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
	sm.entries = make([dynamic]Entry(T), 0, capacity, allocator) or_return
	queue.init(&sm.free_list, capacity, allocator) or_return
	sm._allocator = allocator

	sync.atomic_store(&sm.len, 0)

	return nil
}

destroy :: proc(sm: ^$S/Slot_Map($T)) {
	delete(sm.entries)
	queue.destroy(&sm.free_list)
}

len :: proc(sm: ^$S/Slot_Map($T)) -> int {
	return int(sm.len)
}

insert :: proc(sm: ^$S/Slot_Map($T), value: T) -> Key {
	if queue.len(&sm.free_list) > 0 {
		index, ok := queue.pop(&sm.free_list)

		if !ok {
			return insert(sm, value)
		}

		sm.entries[index].value = value
		sm.entries[index].generation += 1
		sm.len += 1

		return Key{index, sm.entries[index].generation}
	} else {
		index := int(builtin.len(sm.entries))

		append(&sm.entries, Entry(T){0, value})
		sm.len += 1

		return Key{index, 0}
	}
}

remove :: proc(sm: ^$S/Slot_Map($T), key: Key) -> Maybe(T) {
	if contains_key(sm, key) {
		entry := sm.entries[key.index]
		sm.entries[key.index].generation += 1
		queue.push(&sm.free_list, key.index)
		sm.len -= 1
		return entry.value
	} else {
		return nil
	}
}

get :: proc(sm: ^$S/Slot_Map($T), key: Key) -> Maybe(T) {
	if contains_key(sm, key) {
		return sm.entries[key.index].value
	} else {
		return nil
	}
}

contains_key :: proc(sm: ^$S/Slot_Map($T), key: Key) -> bool {
	if key.index >= int(builtin.len(sm.entries)) {
		return false
	}

	if entry := &sm.entries[key.index]; entry.generation != key.generation {
		return false
	}

	return true
}
