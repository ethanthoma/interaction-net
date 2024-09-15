package main

import "core:fmt"
import "core:os"

main :: proc() {
	data, ok := os.read_entire_file("./test.inet")
	assert(ok)
	defer delete(data)

	compiler := make_compiler(string(data))
	ok = compile(&compiler)
}
