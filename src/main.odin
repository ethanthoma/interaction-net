package main

import "core:fmt"

main :: proc() {
	input := `
        @root = a 
            & CON(ERA(), DUP(c, CON(b, DUP(c, b)))) ~ CON(a, DUP(c, CON(b, DUP(c, b))))
    `

	// Create tokenizer
	tokenizer := make_tokenizer(input)
	defer delete_tokenizer(&tokenizer)

	tokenize(&tokenizer)

	// Create parser
	parser := make_parser(tokenizer.tokens[:])
	defer delete_parser(&parser)

	parse(&parser)

	// Extract root def
	root, ok := parser.definitions["root"]
	if !ok do return

	fmt.println(root)
}
