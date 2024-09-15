package main

import "core:fmt"
import "core:os"

main :: proc() {
	data, ok := os.read_entire_file("./test.inet")
	assert(ok)
	defer delete(data)

	// Create tokenizer
	tokenizer := make_tokenizer(string(data))
	defer delete_tokenizer(&tokenizer)

	tokenize(&tokenizer)

	// Create parser
	parser := make_parser(tokenizer.tokens[:])
	defer delete_parser(&parser)

	assert(parse(&parser))

	// Semantic analysis
	assert(check(parser.definitions) == .None)
}
