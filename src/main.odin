package main

import "core:encoding/ansi"
import "core:fmt"
import "core:io"
import "core:os"
import "core:path/filepath"
import "core:strings"

main :: proc() {
	if len(os.args) < 2 {
		print_help()
		os.exit(1)
	}

	command := os.args[1]
	args := os.args[2:]

	switch command {
	case "run":
		cmd_run(args)
	case "example":
		cmd_example(args)
	case:
		print_help()
		os.exit(1)
	}
}

@(private = "file")
error :: proc(msg: string, args: ..any, help: bool = false) {
	if msg != "" {
		fmt.eprint("Error: ")
		fmt.eprintfln(msg, ..args)
	}
	os.exit(1)
}

@(private = "file")
cmd_run :: proc(args: []string) {
	if len(args) != 1 do error("Expected a filename as the first argument")

	filename := args[0]

	data := read_file_or_exit(filename)
	defer delete(data)

	run_text(string(data))
}

@(private = "file")
read_file_or_exit :: proc(filename: string) -> []byte {
	data, ok := os.read_entire_file(filename)
	if !ok do error("Unable to read file '%s'", filename)
	return data
}

@(private = "file")
run_text :: proc(data: string) {
	book, ok := compile(data)
	if !ok do os.exit(1)
	defer delete_book(&book)

	run(&book)
}

@(private = "file")
cmd_example :: proc(args: []string) {
	if len(args) != 1 do error("Expected one argument: an example name")

	name := args[0]

	examples_dir := filepath.join({os.args[0], "../../examples"})

	fd, err := os.open(examples_dir)
	if err != nil do error("Failed to find examples dir")
	defer os.close(fd)

	file_info: []os.File_Info
	file_info, err = os.read_dir(fd, 20)
	if err != nil do error("Failed to read examples dir")

	filenames: [dynamic]string
	found := false
	for fi in file_info {
		if name == filepath.short_stem(fi.name) {
			data := read_file_or_exit(fi.fullpath)
			defer delete(data)

			fmt.printfln("Example %s:", fi.name)
			fmt.println("```inio")
			fmt.print(string(data))
			fmt.println("```")

			run_text(string(data))

			found = true
			break
		}

		append(&filenames, filepath.short_stem(fi.name))
	}

	if !found {
		error("Example not found.  Must be one of %v", filenames)
	}
}

@(private = "file")
print_help :: proc() {
	fmt.println("inio is a simple interaction net runtime in odin")
	fmt.println("Usage:")
	fmt.println("\tinio command [arguments]")
	fmt.println("Commands:")
	fmt.println("\trun [filename]\t\tcompiles and runs the specific file")
	fmt.println("\texample [name]\t\truns the specified example")
}

@(private = "file")
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

	for i in 1 ..< ctx.len {
		fmt.print(ansi.CSI + ansi.FG_BLUE + ansi.SGR + "~" + ansi.CSI + ansi.RESET + ansi.SGR)
	}

	fmt.print(ansi.CSI + ansi.FG_BLUE + ansi.SGR + "^" + ansi.CSI + ansi.RESET + ansi.SGR)
}
