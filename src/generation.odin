package main

import "base:runtime"
import "core:container/queue"
import "core:fmt"
import "core:strings"

Def :: struct {
	nodes:   [dynamic]Pair,
	redexes: queue.Queue(Pair),
	root:    Port,
}

Book :: [dynamic]Def

@(private = "file")
Context :: struct {
	addresses:   map[string]Ref_Address,
	definitions: map[string]Definition,
	parsed_refs: map[string]bool,
	vars:        map[string]Var_Address,
	current:     string,
}

make_book :: proc() -> Book {
	return Book(make([dynamic]Def))
}

delete_book :: proc(book: ^Book) {
	defs := cast(^[dynamic]Def)book
	delete(defs^)
}

generate :: proc(book: ^Book, definitions: map[string]Definition) {
	ctx := Context {
		addresses   = make(map[string]Ref_Address),
		definitions = definitions,
		parsed_refs = make(map[string]bool),
		vars        = make(map[string]Var_Address),
	}
	defer delete(ctx.addresses)
	defer delete(ctx.parsed_refs)
	defer delete(ctx.vars)

	context.user_ptr = &ctx

	generate_definition(book, definitions["root"])
}

@(private = "file")
generate_definition :: proc(book: ^Book, definition: Definition) {
	addr := add_or_get_ref_addr(book, definition.name)

	assign_at_book(book, addr, {nodes = make([dynamic]Pair), redexes = queue.Queue(Pair){}})

	def := &book[addr]

	def.root = generate_term(book, def, definition.root)

	for redex in definition.redexes {
		left := generate_term(book, def, redex.left)
		right := generate_term(book, def, redex.right)
		queue.push_back(&def.redexes, Pair{left, right})
	}

	ctx := cast(^Context)context.user_ptr
	ctx.parsed_refs[definition.name] = true
	for ref, parsed in ctx.parsed_refs {
		(!parsed) or_continue
		generate_definition(book, ctx.definitions[ref])
	}
}

@(private = "file")
assign_at_book :: proc(book: ^Book, addr: Ref_Address, def: Def) {
	defs := cast(^[dynamic]Def)book

	assign_at(defs, int(addr), def)
}

@(private = "file")
add_or_get_ref_addr :: proc(book: ^Book, name: string) -> Ref_Address {
	ctx := cast(^Context)context.user_ptr

	if addr, ok := ctx.addresses[name]; ok do return addr

	if parsed, ok := ctx.parsed_refs[name]; !ok do ctx.parsed_refs[name] = false

	ctx.addresses[name] = Ref_Address(len(ctx.addresses))

	return ctx.addresses[name]
}

@(private = "file")
generate_term :: proc(book: ^Book, def: ^Def, term: ^Term) -> (port: Port) {
	switch term.kind {
	case .VAR:
		ctx := cast(^Context)context.user_ptr
		name := term.data.(Var_Data).name
		if var_addr, exists := ctx.vars[name]; exists {
			return {tag = .VAR, data = var_addr}
		} else {
			var_addr := Var_Address(len(ctx.vars))
			ctx.vars[name] = var_addr
			return {tag = .VAR, data = var_addr}
		}
	case .ERA:
		return {tag = .ERA, data = Empty{}}
	case .REF:
		name := term.data.(Var_Data).name
		addr := add_or_get_ref_addr(book, name)

		return {tag = .REF, data = addr}
	case .CON, .DUP:
		port = Port {
			tag = term.kind,
		}

		node_data := term.data.(Node_Data)
		left_port := generate_term(book, def, node_data.left)
		right_port := generate_term(book, def, node_data.right)

		pair: Pair = {left_port, right_port}

		append(&def.nodes, pair)

		node_index := len(def.nodes) - 1
		port.data = Node_Address(node_index)

		return port
	}

	return port
}

@(private = "file", init)
fmt_book :: proc() {
	if fmt._user_formatters == nil do fmt.set_user_formatters(new(map[typeid]fmt.User_Formatter))

	err := fmt.register_user_formatter(
		type_info_of(Book).id,
		proc(fi: ^fmt.Info, arg: any, verb: rune) -> bool {
			m := cast(^Book)arg.data

			switch verb {
			case 'v':
				fmt.wprintln(fi.writer, "Book{")
				for def, index in m {
					fmt.wprintfln(fi.writer, "%2d: %v", index, def)
				}
				fmt.wprint(fi.writer, "}")
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

	err := fmt.register_user_formatter(
		type_info_of(Def).id,
		proc(fi: ^fmt.Info, arg: any, verb: rune) -> bool {
			m := cast(^Def)arg.data

			switch verb {
			case 'v':
				fmt.wprintfln(fi.writer, "Def{{")

				fmt.wprintfln(fi.writer, "\tNodes:")

				for node, index in m.nodes {
					fmt.wprintfln(fi.writer, "\t\t%2d:\t%v\t,\t%v", index, node.left, node.right)
				}

				fmt.wprintfln(fi.writer, "\tRedexes:")

				for index in 0 ..< queue.len(m.redexes) {
					redex := queue.get(&m.redexes, index)
					fmt.wprintfln(fi.writer, "\t\t%2d:\t%v\t~\t%v", index, redex.left, redex.right)
				}

				fmt.wprintfln(fi.writer, "\tRoot:\t\t%v", m.root)
				fmt.wprintf(fi.writer, "}}")
			case:
				return false
			}

			return true
		},
	)
}
