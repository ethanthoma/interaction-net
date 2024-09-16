package main

Compiler :: struct {
	input: string,
}

make_compiler :: proc(input: string) -> Compiler {
	return {input = input}
}

compile :: proc(c: ^Compiler) -> (program: Program, ok: bool = true) {
	tokenizer := make_tokenizer(c.input)
	defer delete_tokenizer(&tokenizer)

	tokens := tokenize(&tokenizer) or_return

	parser := make_parser(tokens)
	defer delete_parser(&parser)

	definitions := parse(&parser) or_return

	(check(definitions) == .None) or_return

	program = make_program()

	generate(&program, definitions)

	return program, true
}
