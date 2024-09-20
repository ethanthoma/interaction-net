package main

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

	book, compile_ok := compile(string(data))
	if !compile_ok {
		os.exit(1)
	}
	defer delete_book(&book)

	run(&book)
}

compile :: proc(input: string) -> (book: Book, ok: bool = true) {
	tokenizer := make_tokenizer(input)
	defer delete_tokenizer(&tokenizer)

	tokens := tokenize(&tokenizer) or_return

	parser := make_parser(tokens)
	defer delete_parser(&parser)

	definitions := parse(&parser) or_return

	(check(definitions) == .None) or_return

	book = make_book()

	generate(&book, definitions)

	return book, true
}
