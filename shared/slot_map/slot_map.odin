package slot_map

import "base:builtin"
import "base:runtime"
import "core:mem"

DEFAULT_CAPACITY :: 16

Slot_Map :: struct($T: typeid) {
	entries:   [dynamic]Entry(T),
	free_list: [dynamic]u32,
	len:       int,
}

Entry :: struct($T: typeid) {
	generation: u32,
	value:      T,
}

Key :: struct {
	index:      u32,
	generation: u32,
}

init :: proc(
	sm: ^$S/Slot_Map($T),
	capacity := DEFAULT_CAPACITY,
	allocator := context.allocator,
) -> runtime.Allocator_Error {
	sm.entries = make([dynamic]Entry(T), 0, capacity, allocator) or_return
	sm.free_list = make([dynamic]u32, 0, capacity, allocator) or_return

	sm.len = 0

	return nil
}

destroy :: proc(sm: ^$S/Slot_Map($T)) {
	delete(sm.entries)
	delete(sm.free_list)
}

len :: proc(sm: ^$S/Slot_Map($T)) -> int {
	return int(sm.len)
}

insert :: proc(sm: ^$S/Slot_Map($T), value: T) -> Key {
	if builtin.len(sm.free_list) > 0 {
		index, ok := pop_safe(&sm.free_list)

		if !ok {
			return insert(sm, value)
		}

		sm.entries[index].value = value
		sm.entries[index].generation += 1
		sm.len += 1

		return Key{index, sm.entries[index].generation}
	} else {
		index := u32(builtin.len(sm.entries))

		append(&sm.entries, Entry(T){0, value})
		sm.len += 1

		return Key{index, 0}
	}
}

remove :: proc(sm: ^$S/Slot_Map($T), key: Key) -> Maybe(T) {
	if contains_key(sm, key) {
		entry := sm.entries[key.index]
		append(&sm.free_list, key.index)
		sm.len -= 1
		return entry.value
	} else {
		return nil
	}
}

contains_key :: proc(sm: ^$S/Slot_Map($T), key: Key) -> bool {
	if key.index >= u32(builtin.len(sm.entries)) {
		return false
	}

	if entry := &sm.entries[key.index]; entry.generation != key.generation {
		return false
	}

	return true
}
