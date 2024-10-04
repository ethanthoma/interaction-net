package main

import "core:encoding/ansi"
import "core:fmt"
import "core:os"
import "core:path/filepath"

cli :: proc() {
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
cmd_run :: proc(args: []string) {
	if len(args) != 1 {
		error("Expected a filename as the first argument")
	}

	filename := args[0]
	data, ok := os.read_entire_file(filename)
	if !ok {
		error("Unable to read file '%s'\n", filename)
	}
	defer delete(data)

	run_text(string(data))
}

@(private = "file")
cmd_example :: proc(args: []string) {
	if len(args) != 1 {
		error("Expected one argument: an example name")
	}

	name := args[0]
	examples_dir := filepath.join({os.args[0], "../../examples"})

	fd, err := os.open(examples_dir)
	if err != nil {
		error("Failed to find examples dir")
	}
	defer os.close(fd)

	file_info, read_err := os.read_dir(fd, 20)
	if read_err != nil {
		error("Failed to read examples dir")
	}

	filenames: [dynamic]string
	found := false
	for fi in file_info {
		if name == filepath.short_stem(fi.name) {
			data, ok := os.read_entire_file(fi.fullpath)
			if !ok {
				error("Unable to read file '%s'\n", fi.fullpath)
			}
			defer delete(data)

			fmt.printf("Example %s:\n", fi.name)
			fmt.println("```inio")
			fmt.print(string(data))
			fmt.println("```")

			run_text(string(data))

			found = true
			break
		}
	}

	if !found {
		error("Example not found.  Must be one of %v", filenames)
	}
}

@(private = "file")
run_text :: proc(data: string) {
	book, ok := compile(data)
	if !ok {
		os.exit(1)
	}

	run(&book)
}

@(private = "file")
print_help :: proc() {
	fmt.println("inio is a simple interaction net runtime in Odin")
	fmt.println("Usage:")
	fmt.println("\tinio command [arguments]")
	fmt.println("Commands:")
	fmt.println("\trun [filename]\t\tcompiles and runs the specified file")
	fmt.println("\texample [name]\t\truns the specified example")
}

@(private = "file")
error :: proc(msg: string, args: ..any) {
	fmt.eprint(ansi.CSI + ansi.FG_RED + ansi.SGR + "Error" + ansi.CSI + ansi.RESET + ansi.SGR)
	fmt.eprint(": ")
	fmt.eprintf(msg, ..args)
	os.exit(1)
}
