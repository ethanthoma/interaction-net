package main

import "core:encoding/ansi"
import "core:fmt"
import "core:strings"

compile :: proc(input: string) -> (book: Book, ok: bool = true) {
	tokenizer := make_tokenizer(input)
	defer delete_tokenizer(&tokenizer)

	tokens, tokenize_ok := tokenize(&tokenizer)
	if !tokenize_ok {
		compile_error(input, tokenizer.err_ctx)
		return book, false
	}

	parser := make_parser(tokens)
	defer delete_parser(&parser)

	definitions, parse_ok := parse(&parser)
	if !parse_ok {
		compile_error(input, parser.err_ctx)
		return book, false
	}

	err_ctx, check_err := check(definitions)

	if check_err != .None {
		compile_error(input, err_ctx)
		return book, false
	}

	book = make_book()

	generate(&book, definitions)

	return book, true
}

Error_Context :: struct {
	line, column, len: int,
}

@(private = "file")
compile_error :: proc(input: string, ctx: Error_Context) {
	lines := strings.split_lines(input)
	defer delete(lines)

	fmt.println(lines[ctx.line - 1])
	pad := strings.right_justify("", ctx.column - 1, " ")
	fmt.print(pad)

	for _ in 1 ..< ctx.len {
		fmt.print(ansi.CSI + ansi.FG_BLUE + ansi.SGR + "~" + ansi.CSI + ansi.RESET + ansi.SGR)
	}

	fmt.print(ansi.CSI + ansi.FG_BLUE + ansi.SGR + "^" + ansi.CSI + ansi.RESET + ansi.SGR)
}
