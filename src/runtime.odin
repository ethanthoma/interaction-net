package main

import "core:container/queue"
import "core:fmt"

ROOT :: Ref_Address(0)
NONE :: Var_Address(1 << 32 - 1)

Program :: struct {
	nodes:   [dynamic]Maybe_Pair,
	redexes: queue.Queue(Pair),
	vars:    [dynamic]Maybe_Port,
}

Maybe_Port :: union {
	Empty,
	Port,
}

Maybe_Pair :: union {
	Empty,
	Pair,
}

@(private = "file")
Context :: struct {
	book: ^Book,
}

run :: proc(book: ^Book) {
	ctx := Context{book}
	context.user_ptr = &ctx

	program: Program = {
		nodes = make([dynamic]Maybe_Pair),
		vars  = make([dynamic]Maybe_Port),
	}
	queue.init(&program.redexes)

	defer delete(program.nodes)
	defer queue.destroy(&program.redexes)
	defer delete(program.vars)

	assign_at(&program.vars, 0, Empty{})
	queue.push_front(&program.redexes, Pair{{.REF, ROOT}, {.VAR, Var_Address(0)}})

	fmt.println(program)

	for {
		redex := queue.pop_front_safe(&program.redexes) or_break
		interact(&program, redex)
	}
}

@(private = "file")
interact :: proc(program: ^Program, redex: Pair) {
	a, b := redex.left, redex.right

	if a.tag == .REF && b == {.VAR, Var_Address(0)} do call(program, redex)

	if a.tag < b.tag do a, b = b, a

	tags := struct {
		tag_a: Term_Kind,
		tag_b: Term_Kind,
	}({a.tag, b.tag})

	switch tags {
	case {.CON, .DUP}, {.DUP, .CON}:
		commute(program, redex)
	case {.CON, .ERA}, {.ERA, .CON}:
		erase(program, redex)
	case {.DUP, .ERA}, {.ERA, .DUP}:
		erase(program, redex)
	case {.CON, .CON}:
		annihilate(program, redex)
	case {.DUP, .DUP}:
		annihilate(program, redex)
	case {.ERA, .ERA}:
		void(program, redex)
	case {.REF, .REF}:
		void(program, redex)
	case {.REF, .ERA}, {.ERA, .REF}:
		void(program, redex)
	case {.REF, .CON}, {.CON, .REF}:
		call(program, redex)
	case {.REF, .DUP}, {.DUP, .REF}:
		erase(program, redex)
	case:
		if a.tag == .VAR || b.tag == .VAR {
			link(program, redex)
		} else {
			fmt.eprintfln("Missing rule for %v:%v", a.tag, b.tag)
		}
	}
}

@(private = "file")
commute :: proc(program: ^Program, redex: Pair) {
	fmt.println("interact: COMM")

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

	new_con1 := create_node(program, .CON, x2, x1)
	new_con2 := create_node(program, .CON, y2, y1)

	new_dup1 := create_node(program, .DUP, y2, x2)
	new_dup2 := create_node(program, .DUP, y1, x1)

	link(program, Pair{new_dup1, con_node.right})
	link(program, Pair{new_dup2, con_node.left})
	link(program, Pair{new_con1, dup_node.right})
	link(program, Pair{new_con2, dup_node.left})

	delete_node(program, con_addr)
	delete_node(program, dup_addr)
}

@(private = "file")
create_var :: proc(program: ^Program) -> Var_Address {
	addr := len(program.vars)
	var := Port{.VAR, NONE}
	append(&program.vars, var)
	return Var_Address(addr)
}

@(private = "file")
annihilate :: proc(program: ^Program, redex: Pair) {
	fmt.println("interact: ANNI")

	a, b := redex.left, redex.right

	address_a := a.data.(Node_Address)
	address_b := b.data.(Node_Address)

	node_a := program.nodes[address_a].(Pair)
	node_b := program.nodes[address_b].(Pair)

	#partial switch a.tag {
	case .CON:
		link(program, {node_a.left, node_b.right})
		link(program, {node_a.right, node_b.left})
	case .DUP:
		link(program, {node_a.left, node_b.left})
		link(program, {node_a.right, node_b.right})
	}

	delete_node(program, address_a)
	delete_node(program, address_b)
}

@(private = "file")
void :: proc(program: ^Program, redex: Pair) {
	fmt.println("interact: VOID")
}

@(private = "file")
erase :: proc(program: ^Program, redex: Pair) {
	fmt.println("interact: ERAS")
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
	link(program, {a, node.left})
	link(program, {a, node.right})

	delete_node(program, node_addr)
}

@(private = "file")
link :: proc(program: ^Program, redex: Pair) {
	fmt.println("interact: LINK")

	a, b := redex.left, redex.right

	for {
		if a.tag != .VAR {
			a, b = b, a
		}

		if a.tag != .VAR {
			queue.push_back(&program.redexes, Pair{a, b})
			return
		}

		b = enter(program, b)

		var_addr := a.data.(Var_Address)

		switch new_a in vars_exchange(program, var_addr, b) {
		case Port:
			vars_take(program, var_addr)
			a = new_a
		case Empty:
			return
		}
	}
}

enter :: proc(program: ^Program, var: Port) -> Port {
	var := var

	loop: for var.tag == .VAR {
		addr := var.data.(Var_Address)
		val := vars_exchange(program, addr, Empty{})
		switch val in val {
		case Empty:
			break loop
		case Port:
			vars_take(program, addr)
			var = val
		}
	}

	return var
}

vars_exchange :: proc(
	program: ^Program,
	addr: Var_Address,
	new_port: Maybe_Port,
) -> (
	old_port: Maybe_Port,
) {
	old_port = program.vars[addr]
	program.vars[addr] = new_port
	return old_port
}

vars_take :: proc(program: ^Program, addr: Var_Address) {
	vars_exchange(program, addr, Empty{})
}

@(private = "file")
call :: proc(program: ^Program, redex: Pair) {
	fmt.println("interact: CALL")
	addr := redex.left.data.(Ref_Address)

	// copy from book
	assert(false, "CALL not implemented")
}

@(private = "file")
delete_node :: proc(program: ^Program, address: Node_Address) {
	program.nodes[address] = Empty{}
}

@(private = "file")
create_node :: proc(program: ^Program, kind: Term_Kind, var_left, var_right: Var_Address) -> Port {
	left := Port{.VAR, var_left}
	right := Port{.VAR, var_right}
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

@(private = "file", init)
fmt_program :: proc() {
	if fmt._user_formatters == nil do fmt.set_user_formatters(new(map[typeid]fmt.User_Formatter))

	err := fmt.register_user_formatter(
		type_info_of(Program).id,
		proc(fi: ^fmt.Info, arg: any, verb: rune) -> bool {
			m := cast(^Program)arg.data

			switch verb {
			case 'v':
				fmt.wprintfln(fi.writer, "Program{{")

				fmt.wprintfln(fi.writer, "\tNodes:")

				for node, index in m.nodes {
					fmt.wprintf(fi.writer, "\t\t%2d:\t", index)
					switch node in node {
					case Empty:
						fmt.wprintfln(fi.writer, "EMPTY\t,\t,EMPTY")
					case Pair:
						fmt.wprintfln(fi.writer, "%v\t,\t%v", node.left, node.right)
					}
				}

				fmt.wprintfln(fi.writer, "\tRedexes:")

				for index in 0 ..< queue.len(m.redexes) {
					redex := queue.get(&m.redexes, index)
					fmt.wprintfln(fi.writer, "\t\t%2d:\t%v\t~\t%v", index, redex.left, redex.right)
				}

				fmt.wprintfln(fi.writer, "\tVars:")

				for var, index in m.vars {
					fmt.wprintf(fi.writer, "\t\t%2d:\t", index)
					switch var in var {
					case Empty:
						fmt.wprintfln(fi.writer, "EMPTY")
					case Port:
						fmt.wprintfln(fi.writer, "%v", var)
					}
				}

				fmt.wprintf(fi.writer, "}}")
			case:
				return false
			}

			return true
		},
	)
}
