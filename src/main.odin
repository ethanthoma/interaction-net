package main

import "core:fmt"
import "core:thread"
import "shared:slot_map"

main :: proc() {
	CAPACITY :: 8

	s: slot_map.Slot_Map(int)
	slot_map.init(&s, CAPACITY)

	key := slot_map.insert(&s, 32)

	fmt.println(s)
}
