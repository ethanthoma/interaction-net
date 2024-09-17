package main

import "base:runtime"
import "core:container/queue"
import "core:fmt"
import "core:io"
import "core:strings"

Program :: struct {
	nodes:   [dynamic]Maybe_Pair,
	redexes: queue.Queue(Pair),
	vars:    [dynamic]Port,
}

Maybe_Pair :: union {
	Pair,
	Empty,
}

@(private = "file")
Context :: struct {
	addresses:   map[string]Var_Address,
	definitions: map[string]Definition,
	parsed_refs: map[string]bool,
	vars:        map[string]Var_Address,
	current:     string,
}

make_program :: proc() -> (program: Program) {
	program = {
		nodes   = make([dynamic]Maybe_Pair),
		redexes = queue.Queue(Pair){},
		vars    = make([dynamic]Port),
	}
	queue.init(&program.redexes)

	return program
}

delete_program :: proc(program: ^Program) {
	delete(program.nodes)
	delete(program.vars)

	queue.destroy(&program.redexes)
}

generate :: proc(program: ^Program, definitions: map[string]Definition) {
	ctx := Context {
		addresses   = make(map[string]Var_Address),
		definitions = definitions,
		parsed_refs = make(map[string]bool),
		vars        = make(map[string]Var_Address),
	}
	defer delete(ctx.addresses)
	defer delete(ctx.parsed_refs)
	defer delete(ctx.vars)

	def := definitions["root"]
	generate_definition(program, &def, &ctx)
}

@(private = "file")
generate_definition :: proc(program: ^Program, def: ^Definition, ctx: ^Context) {
	ctx.current = def.name

	if def.name not_in ctx.addresses {
		var_index := len(program.vars)
		ctx.addresses[def.name] = Var_Address(var_index)
		append(&program.vars, Port{})
	}

	node_index := len(program.nodes)

	root_port := generate_term(program, def.root, ctx)

	for redex in def.redexes {
		left := generate_term(program, redex.left, ctx)
		right := generate_term(program, redex.right, ctx)
		queue.push_back(&program.redexes, Pair{left, right})
	}

	ctx.parsed_refs[def.name] = true

	address := ctx.addresses[def.name]
	program.vars[address] = root_port

	for ref, parsed in ctx.parsed_refs {
		(!parsed) or_continue
		def := &ctx.definitions[ref]
		generate_definition(program, def, ctx)
	}
}

@(private = "file")
generate_term :: proc(program: ^Program, term: ^Term, ctx: ^Context) -> (port: Port) {
	switch term.kind {
	case .VAR:
		full_name := strings.concatenate({ctx.current, term.data.(Var_Data).name})
		if var_addr, exists := ctx.vars[full_name]; exists {
			return {tag = .VAR, data = var_addr}
		} else {
			var_addr := Var_Address(len(ctx.vars))
			ctx.vars[full_name] = var_addr
			return {tag = .VAR, data = var_addr}
		}
	case .ERA:
		return {tag = .ERA, data = Empty{}}
	case .REF:
		ref_name := term.data.(Var_Data).name

		if ref_name not_in ctx.addresses {
			var_index := len(program.vars)
			ctx.addresses[ref_name] = Var_Address(var_index)
			append(&program.vars, Port{})
			ctx.parsed_refs[ref_name] = false
		}

		address := ctx.addresses[ref_name]

		return {tag = .REF, data = address}
	case .CON, .DUP:
		port = Port {
			tag = term.kind,
		}

		node_data := term.data.(Node_Data)
		left_port := generate_term(program, node_data.left, ctx)
		right_port := generate_term(program, node_data.right, ctx)

		pair: Pair = {left_port, right_port}

		append(&program.nodes, pair)

		node_index := len(program.nodes) - 1
		port.data = Node_Address(node_index)

		return port
	}

	return port
}

@(private = "file", init)
format_program :: proc() {
	fmt.set_user_formatters(new(map[typeid]fmt.User_Formatter))
	err := fmt.register_user_formatter(
		type_info_of(Program).id,
		proc(fi: ^fmt.Info, arg: any, verb: rune) -> bool {
			m := cast(^Program)arg.data
			switch verb {
			case 'v':
				io.write_string(fi.writer, "Program{\n", &fi.n)
				io.write_string(fi.writer, "\tRedexes:\n", &fi.n)

				port_type_info := runtime.type_info_base(type_info_of(typeid_of(Port))).variant.(runtime.Type_Info_Struct)

				for index in 0 ..< queue.len(m.redexes) {
					redex := queue.get(&m.redexes, index)
					io.write_string(fi.writer, "\t\t", &fi.n)
					fmt.fmt_struct(fi, redex.left, 'v', port_type_info, "")
					io.write_string(fi.writer, " ~ ", &fi.n)
					fmt.fmt_struct(fi, redex.right, 'v', port_type_info, "")
					io.write_string(fi.writer, "\n", &fi.n)
				}

				io.write_string(fi.writer, "\tNodes:\n", &fi.n)

				for node, index in m.nodes {
					#partial switch n in node {
					case Pair:
						io.write_string(fi.writer, "\t\t", &fi.n)
						io.write_int(fi.writer, index)
						io.write_string(fi.writer, ":\t(", &fi.n)
						fmt.fmt_struct(fi, n.left, 'v', port_type_info, "")
						io.write_string(fi.writer, ", ", &fi.n)
						fmt.fmt_struct(fi, n.right, 'v', port_type_info, "")
						io.write_string(fi.writer, ")\n", &fi.n)
					}
				}

				io.write_string(fi.writer, "\tVars:\n", &fi.n)
				for port, index in m.vars {
					io.write_string(fi.writer, "\t\t", &fi.n)
					io.write_int(fi.writer, index)
					io.write_string(fi.writer, ":\t", &fi.n)
					fmt.fmt_struct(fi, port, 'v', port_type_info, "")
					io.write_string(fi.writer, "\n", &fi.n)
				}
				io.write_string(fi.writer, "}", &fi.n)
			case:
				return false
			}
			return true
		},
	)
}
