package main

import "core:fmt"

main :: proc() {
	input := `
        @root = a 
            & @second ~ CON(a, @first)

        @first = DUP(a, CON(b, DUP(a, b)))

        @second = CON(ERA(), @first)
    `

	// Create tokenizer
	tokenizer := make_tokenizer(input)
	defer delete_tokenizer(&tokenizer)

	tokenize(&tokenizer)

	// Create parser
	parser := make_parser(tokenizer.tokens[:])
	defer delete_parser(&parser)

	assert(parse(&parser))

	// Semantic analysis
	assert(check(parser.definitions) == .None)
}
