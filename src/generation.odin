package main

import "core:fmt"

Def :: struct {
	nodes:   [dynamic]Pair,
	redexes: [dynamic]Pair,
	numbers: [dynamic]u32,
	root:    Port,
	vars:    int,
}

Book :: struct {
	defs:  [dynamic]Def,
	names: [dynamic]string,
}

@(private = "file")
Context :: struct {
	addresses:   map[string]Ref_Data,
	definitions: map[string]Definition,
	parsed_refs: map[string]bool,
	vars:        map[string]Var_Data,
}

make_book :: proc() -> Book {
	book: Book

	book.defs = make([dynamic]Def)
	book.names = make([dynamic]string)

	return book
}

delete_book :: proc(book: ^Book) {
	delete(book.defs)
	delete(book.names)
}

generate :: proc(book: ^Book, definitions: map[string]Definition) {
	ctx := Context {
		addresses   = make(map[string]Ref_Data),
		definitions = definitions,
		parsed_refs = make(map[string]bool),
		vars        = make(map[string]Var_Data),
	}
	defer delete(ctx.addresses)
	defer delete(ctx.parsed_refs)
	defer delete(ctx.vars)

	context.user_ptr = &ctx

	generate_definition(book, definitions["root"])
}

@(private = "file")
generate_definition :: proc(book: ^Book, definition: Definition) {
	addr := add_or_get_ref_addr(book, definition.name).addr

	assign_at(
		&book.defs,
		int(addr),
		Def {
			nodes = make([dynamic]Pair),
			redexes = make([dynamic]Pair),
			numbers = make([dynamic]u32),
		},
	)
	assign_at(&book.names, int(addr), definition.name)

	def := &book.defs[addr]

	def.root = generate_term(book, def, definition.root)

	for redex in definition.redexes {
		left := generate_term(book, def, redex.left)
		right := generate_term(book, def, redex.right)
		append(&def.redexes, Pair{left, right})
	}

	ctx := cast(^Context)context.user_ptr

	def.vars = len(ctx.vars)

	ctx.parsed_refs[definition.name] = true
	for ref, parsed in ctx.parsed_refs {
		(!parsed) or_continue
		generate_definition(book, ctx.definitions[ref])
	}
}

@(private = "file")
add_or_get_ref_addr :: proc(book: ^Book, name: string) -> Ref_Data {
	ctx := cast(^Context)context.user_ptr

	if addr, ok := ctx.addresses[name]; ok do return addr

	if _, ok := ctx.parsed_refs[name]; !ok do ctx.parsed_refs[name] = false

	ctx.addresses[name] = Ref_Data(len(ctx.addresses))

	return ctx.addresses[name]
}

@(private = "file")
generate_term :: proc(book: ^Book, def: ^Def, term: ^Term) -> (port: Port) {
	ctx := cast(^Context)context.user_ptr

	port.tag = term.kind

	switch term.kind {
	case .VAR:
		name := term.payload.(Var_Payload).name
		if var_addr, exists := ctx.vars[name]; exists {
			port.data = transmute(u32)var_addr
		} else {
			var_addr = Var_Data {
				addr = len(ctx.vars),
			}
			ctx.vars[name] = var_addr
			port.data = transmute(u32)var_addr
		}
	case .ERA:
		port.data = transmute(u32)Empty{}
	case .REF:
		name := term.payload.(Var_Payload).name
		port.data = transmute(u32)add_or_get_ref_addr(book, name)
	case .CON, .DUP, .SWI:
		node_payload := term.payload.(Node_Payload)

		left_port := generate_term(book, def, node_payload.left)
		right_port := generate_term(book, def, node_payload.right)

		pair: Pair = {left_port, right_port}

		addr := len(def.nodes)

		port.data = transmute(u32)Node_Data{addr = addr}

		append(&def.nodes, pair)
	case .NUM:
		type := term.payload.(Num_Payload).type
		addr := len(def.numbers)

		port.data = transmute(u32)Num_Data{type = type, addr = addr}

		value: u32
		switch v in term.payload.(Num_Payload).value {
		case u32:
			value = v
		case i32:
			value = transmute(u32)v
		case f32:
			value = transmute(u32)v
		}

		append(&def.numbers, value)
	case .OPE:
		node_payload := term.payload.(Op_Payload).node
		left_port := generate_term(book, def, node_payload.left)
		right_port := generate_term(book, def, node_payload.right)

		pair: Pair = {left_port, right_port}

		type := term.payload.(Op_Payload).type
		addr := len(def.nodes)

		append(&def.nodes, pair)

		port.data = transmute(u32)Op_Data{type = type, addr = addr}
	}

	return port
}

@(private = "file", init)
fmt_book :: proc() {
	if fmt._user_formatters == nil do fmt.set_user_formatters(new(map[typeid]fmt.User_Formatter))

	fmt.register_user_formatter(
		type_info_of(Book).id,
		proc(fi: ^fmt.Info, arg: any, verb: rune) -> bool {
			m := cast(^Book)arg.data

			switch verb {
			case 'v':
				fmt.wprintln(fi.writer, "Book[")
				for def, index in m.defs {
					fmt.wprintfln(fi.writer, "\t@%v: %v,", m.names[index], def)
				}
				fmt.wprint(fi.writer, "]")
			case:
				return false
			}

			return true
		},
	)
}

@(private = "file", init)
fmt_def :: proc() {
	if fmt._user_formatters == nil do fmt.set_user_formatters(new(map[typeid]fmt.User_Formatter))

	fmt.register_user_formatter(
		type_info_of(Def).id,
		proc(fi: ^fmt.Info, arg: any, verb: rune) -> bool {
			m := cast(^Def)arg.data

			switch verb {
			case 'v':
				fmt.wprintln(fi.writer, "Def{")

				fmt.wprintln(fi.writer, "\t\tNodes:")

				for node, index in m.nodes {
					fmt.wprintfln(fi.writer, "\t\t\t%2d:\t%d\t,\t%d", index, node.left, node.right)
				}

				fmt.wprintln(fi.writer, "\t\tRedexes:")

				for redex, index in m.redexes {
					fmt.wprintfln(
						fi.writer,
						"\t\t\t%2d:\t%d\t~\t%d",
						index,
						redex.left,
						redex.right,
					)
				}

				fmt.wprintln(fi.writer, "\t\tNums:")

				for number, index in m.numbers {
					fmt.wprintfln(fi.writer, "\t\t\t%2d:\t%v", index, number)
				}

				fmt.wprintfln(fi.writer, "\t\tRoot:\t\t%d", m.root)
				fmt.wprint(fi.writer, "\t}")
			case:
				return false
			}

			return true
		},
	)
}
