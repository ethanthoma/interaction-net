package main

import "core:fmt"
import "shared:slot_map"

main :: proc() {
	CAPACITY :: 8

	s: slot_map.Slot_Map(int)
	slot_map.init(&s, CAPACITY)

	key, ok := slot_map.insert(&s, 32)

	fmt.println(key, ok, s)
}
