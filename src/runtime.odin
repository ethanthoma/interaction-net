package main

import "core:container/queue"
import "core:fmt"

@(private = "file")
Context :: struct {
	substitutions: map[Var_Address]Port,
}

run :: proc(program: ^Program) {
	ctx := Context {
		substitutions = make(map[Var_Address]Port),
	}
	defer delete(ctx.substitutions)

	boot: Pair = {{.REF, Var_Address(len(program.vars))}, {.REF, Var_Address(0)}}
	queue.push_front(&program.redexes, boot)

	for {
		redex := queue.pop_front_safe(&program.redexes) or_break
		interact(program, redex, &ctx)
	}

	for &var in program.vars {
		var = enter(program, var, &ctx)
	}

	fmt.println(ctx.substitutions)
}

interact :: proc(program: ^Program, redex: Pair, ctx: ^Context) {
	a, b := redex.left, redex.right

	tags := struct {
		tag_a: Term_Kind,
		tag_b: Term_Kind,
	}({a.tag, b.tag})

	switch tags {
	case {.CON, .DUP}, {.DUP, .CON}:
		commute(program, redex, ctx)
	case {.CON, .ERA}, {.ERA, .CON}:
		erase(program, redex, ctx)
	case {.DUP, .ERA}, {.ERA, .DUP}:
		erase(program, redex, ctx)
	case {.CON, .CON}:
		annihilate(program, redex, ctx)
	case {.DUP, .DUP}:
		annihilate(program, redex, ctx)
	case {.ERA, .ERA}:
		void(program, redex, ctx)
	case {.REF, .REF}:
		void(program, redex, ctx)
	case {.REF, .ERA}, {.ERA, .REF}:
		void(program, redex, ctx)
	case {.REF, .CON}, {.CON, .REF}:
		call(program, redex, ctx)
	case {.REF, .DUP}, {.DUP, .REF}:
		erase(program, redex, ctx)
	case:
		if a.tag == .VAR || b.tag == .VAR {
			link(program, redex, ctx)
		} else {
			fmt.eprintfln("Missing rule for %v:%v", a.tag, b.tag)
		}
	}
}

@(private = "file")
commute :: proc(program: ^Program, redex: Pair, ctx: ^Context) {
	fmt.println("interact: γδ")

	con, dup := redex.left, redex.right
	if con.tag == .DUP {
		con, dup = dup, con
	}

	con_addr := con.data.(Node_Address)
	dup_addr := dup.data.(Node_Address)

	con_node := program.nodes[con_addr].(Pair)
	dup_node := program.nodes[dup_addr].(Pair)

	x1 := create_var(program)
	x2 := create_var(program)
	y1 := create_var(program)
	y2 := create_var(program)

	new_con1 := create_node(program, .CON, x1, x2)
	new_con2 := create_node(program, .CON, y1, y2)

	new_dup1 := create_node(program, .DUP, x1, y1)
	new_dup2 := create_node(program, .DUP, x2, y2)

	link(program, Pair{new_con1, con_node.left}, ctx)
	link(program, Pair{new_con2, con_node.right}, ctx)
	link(program, Pair{new_dup1, dup_node.left}, ctx)
	link(program, Pair{new_dup2, dup_node.right}, ctx)

	delete_node(program, con_addr)
	delete_node(program, dup_addr)
}

@(private = "file")
create_var :: proc(program: ^Program) -> Port {
	@(static)
	addr := -1

	if addr == -1 {
		addr = len(program.vars)

		var := Port {
			tag  = .VAR,
			data = Var_Address(1 << 32 - 1),
		}

		append(&program.vars, var)
		return var
	}

	return program.vars[addr]
}

@(private = "file")
annihilate :: proc(program: ^Program, redex: Pair, ctx: ^Context) {
	fmt.println("interact: γγ | δδ")

	a, b := redex.left, redex.right

	address_a := a.data.(Node_Address)
	address_b := b.data.(Node_Address)

	node_a := program.nodes[address_a].(Pair)
	node_b := program.nodes[address_b].(Pair)

	#partial switch a.tag {
	case .CON:
		link(program, {node_a.left, node_b.right}, ctx)
		link(program, {node_a.right, node_b.left}, ctx)
	case .DUP:
		link(program, {node_a.left, node_b.left}, ctx)
		link(program, {node_a.right, node_b.right}, ctx)
	}

	delete_node(program, address_a)
	delete_node(program, address_b)
}

@(private = "file")
void :: proc(program: ^Program, redex: Pair, ctx: ^Context) {
	fmt.println("interact: εε | REF:REF | REF:ε")
}

@(private = "file")
erase :: proc(program: ^Program, redex: Pair, ctx: ^Context) {
	fmt.println("interact: γε | δε | REF:δ")
	a, b := redex.left, redex.right

	#partial switch a.tag {
	case .CON:
		a, b = b, a
	case .DUP:
		a, b = b, a
	}

	// a is ERA or REF
	// b is CON or DUP
	node_addr := b.data.(Node_Address)
	node := program.nodes[node_addr].(Pair)

	// Erase both ports of the node
	link(program, {a, node.left}, ctx)
	link(program, {a, node.right}, ctx)

	delete_node(program, node_addr)
}

@(private = "file")
link :: proc(program: ^Program, redex: Pair, ctx: ^Context) {
	fmt.println("interact: VAR:_")

	a, b := redex.left, redex.right

	for {
		if a.tag != .VAR {
			a, b = b, a
		}

		if a.tag != .VAR {
			queue.push_back(&program.redexes, Pair{a, b})
			break
		}

		b = enter(program, b, ctx)

		var_name := a.data.(Var_Address)
		got, exists := ctx.substitutions[var_name]

		if !exists {
			ctx.substitutions[var_name] = b
			break
		} else {
			delete_key(&ctx.substitutions, var_name)
			a = got
		}
	}
}

@(private = "file")
call :: proc(program: ^Program, redex: Pair, ctx: ^Context) {
	fmt.println("interact: REF:γ")
	var_addr := redex.left.data.(Var_Address)
	port := program.vars[var_addr]

	link(program, {port, redex.right}, ctx)
}

@(private = "file")
delete_node :: proc(program: ^Program, address: Node_Address) {
	program.nodes[address] = Empty{}
}

@(private = "file")
create_node :: proc(program: ^Program, kind: Term_Kind, left, right: Port) -> Port {
	for i := 0; i < len(program.nodes); i += 1 {
		#partial switch _ in &program.nodes[i] {
		case Empty:
			program.nodes[i] = Pair{left, right}
			return Port{tag = kind, data = Node_Address(i)}
		}
	}
	append(&program.nodes, Pair{left, right})
	return Port{tag = kind, data = Node_Address(len(program.nodes) - 1)}
}

@(private = "file")
enter :: proc(program: ^Program, port: Port, ctx: ^Context) -> Port {
	port := port

	for port.tag == .VAR {
		var_addr := port.data.(Var_Address)
		port = ctx.substitutions[var_addr] or_break
		delete_key(&ctx.substitutions, var_addr)
	}

	return port
}
