package main

import "core:container/queue"

Program :: struct {
	nodes:   [dynamic]Pair,
	redexes: queue.Queue(Pair),
	vars:    map[string]Port,
	refs:    [dynamic]Port,
}

@(private = "file")
Context :: struct {
	addresses:   map[string]Ref_Address,
	definitions: map[string]Definition,
	parsed_refs: map[string]bool,
}

make_program :: proc() -> (program: Program) {
	program = {
		nodes   = make([dynamic]Pair),
		redexes = queue.Queue(Pair){},
		vars    = make(map[string]Port),
		refs    = make([dynamic]Port),
	}
	queue.init(&program.redexes)

	return program
}

delete_program :: proc(program: ^Program) {
	delete(program.nodes)
	delete(program.vars)
	delete(program.refs)

	queue.destroy(&program.redexes)
}

generate :: proc(program: ^Program, definitions: map[string]Definition) {
	ctx := Context {
		addresses   = make(map[string]Ref_Address),
		definitions = definitions,
		parsed_refs = make(map[string]bool),
	}
	defer delete(ctx.addresses)
	defer delete(ctx.parsed_refs)

	def := definitions["root"]
	generate_definition(program, &def, &ctx)
}

@(private = "file")
generate_definition :: proc(program: ^Program, def: ^Definition, ctx: ^Context) {
	if def.name not_in ctx.addresses {
		ref_index := len(program.refs)
		ctx.addresses[def.name] = Ref_Address(ref_index)
		append(&program.refs, Port{})
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
	program.refs[address] = root_port

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
		var_name := term.data.(Var_Data).name
		if existing_port, exists := program.vars[var_name]; exists {
			return existing_port
		} else {
			port = Port {
				tag  = .VAR,
				data = Var_Name(var_name),
			}
			program.vars[var_name] = port
			return port
		}
	case .ERA:
		return {tag = .ERA, data = Empty{}}
	case .REF:
		ref_name := term.data.(Var_Data).name

		if ref_name not_in ctx.addresses {
			ref_index := len(program.refs)
			ctx.addresses[ref_name] = Ref_Address(ref_index)
			append(&program.refs, Port{})
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
