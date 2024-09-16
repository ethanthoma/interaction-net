package main

import "core:container/queue"
import "core:fmt"
import "core:os"

main :: proc() {
	if len(os.args) != 2 {
		fmt.eprintln("Expected a filename as the first argument")
		os.exit(1)
	}

	filename := os.args[1]

	data, read_ok := os.read_entire_file(filename)
	if !read_ok {
		fmt.eprintfln("Unable to read the passed file %s", filename)
		os.exit(1)
	}
	defer delete(data)

	compiler := make_compiler(string(data))
	program, compile_ok := compile(&compiler)
	if !compile_ok {
		fmt.eprintfln("Failed to compiled %s", filename)
		os.exit(1)
	}
	defer delete_program(&program)

	run(&program)
}
