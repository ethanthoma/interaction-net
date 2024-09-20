package main

import "core:container/queue"
import "core:fmt"
import "core:time"

ROOT :: 0

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
	book:         ^Book,
	interactions: int,
}

run :: proc(book: ^Book) {
	ctx := Context{book, 0}
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
	queue.push_front(&program.redexes, Pair{{.REF, Ref_Address(ROOT)}, {.VAR, Var_Address(ROOT)}})

	timer := time.Stopwatch{}

	time.stopwatch_start(&timer)

	for {
		redex := queue.pop_front_safe(&program.redexes) or_break
		interact(&program, redex)
	}

	time.stopwatch_stop(&timer)

	fmt.println(enter(&program, {.VAR, Var_Address(0)}))
	fmt.printfln("Interactions:\t%d", ctx.interactions)
	fmt.printfln("Time:\t%v", time.stopwatch_duration(timer))
	fmt.printfln(
		"MIps:\t%f",
		(f64(ctx.interactions) / 1_000_000) /
		time.duration_seconds(time.stopwatch_duration(timer)),
	)
}

@(private = "file")
interact :: proc(program: ^Program, redex: Pair) {
	a, b := redex.left, redex.right
	ctx := cast(^Context)context.user_ptr

	if a.tag < b.tag do a, b = b, a

	tags := struct {
		tag_a: Term_Kind,
		tag_b: Term_Kind,
	}({a.tag, b.tag})
	switch tags {
	case {.DUP, .CON}:
		commute(program, redex)
	case {.CON, .ERA}, {.DUP, .ERA}, {.DUP, .REF}:
		erase(program, redex)
	case {.CON, .CON}, {.DUP, .DUP}:
		annihilate(program, redex)
	case {.ERA, .ERA}, {.REF, .REF}, {.REF, .ERA}:
		void(program, redex)
	case {.CON, .REF}:
		call(program, redex)
	case:
		if a.tag == .REF && b == {.VAR, Var_Address(0)} do call(program, redex)
		else if a.tag == .VAR || b.tag == .VAR {
			link(program, redex)
			ctx.interactions -= 1
		} else do fmt.eprintfln("Missing rule for %v:%v", a.tag, b.tag)
	}

	ctx.interactions += 1
}

@(private = "file")
commute :: proc(program: ^Program, redex: Pair) {
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
	x3 := create_var(program)
	x4 := create_var(program)

	node_1 := create_node(program, .CON, x1, x2)
	node_2 := create_node(program, .CON, x3, x4)
	node_3 := create_node(program, .DUP, x1, x3)
	node_4 := create_node(program, .DUP, x2, x4)

	link(program, {node_1, dup_node.left})
	link(program, {node_2, dup_node.right})
	link(program, {node_3, con_node.left})
	link(program, {node_4, con_node.right})

	delete_node(program, con_addr)
	delete_node(program, dup_addr)
}

@(private = "file")
create_var :: proc(program: ^Program) -> Var_Address {
	addr := len(program.vars)
	append(&program.vars, Empty{})
	return Var_Address(addr)
}

@(private = "file")
annihilate :: proc(program: ^Program, redex: Pair) {
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
void :: proc(program: ^Program, redex: Pair) {}

@(private = "file")
erase :: proc(program: ^Program, redex: Pair) {
	a, b := redex.left, redex.right

	#partial switch a.tag {
	case .CON, .DUP:
		a, b = b, a
	}

	// a is ERA or REF
	// b is CON or DUP
	node_addr := b.data.(Node_Address)
	node := program.nodes[node_addr].(Pair)

	delete_node(program, node_addr)

	// Erase both ports of the node
	link(program, {a, node.left})
	link(program, {a, node.right})
}

@(private = "file")
link :: proc(program: ^Program, redex: Pair) {
	a, b := redex.left, redex.right

	loop: for {
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
			break loop
		}
	}
}

@(private = "file")
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

@(private = "file")
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

@(private = "file")
vars_take :: proc(program: ^Program, addr: Var_Address) {
	vars_exchange(program, addr, Empty{})
}

@(private = "file")
call :: proc(program: ^Program, redex: Pair) {
	a, b := redex.left, redex.right

	if a.tag != .REF do a, b = b, a

	addr := a.data.(Ref_Address)

	def := (cast(^Context)context.user_ptr).book[addr]

	offset_vars := len(program.vars)
	offset_node := len(program.nodes)
	adjust_addr := proc(port: Port, offset_vars, offset_node: int) -> Port {
		port := port

		#partial switch port.tag {
		case .CON, .DUP:
			port.data = Node_Address(offset_node + int(port.data.(Node_Address)))
		case .VAR:
			port.data = Var_Address(offset_vars + int(port.data.(Var_Address)))
		}

		return port
	}

	for var in 0 ..< def.vars {
		create_var(program)
	}

	for node in def.nodes {
		left := node.left
		right := node.right


		left = adjust_addr(left, offset_vars, offset_node)
		right = adjust_addr(right, offset_vars, offset_node)

		for i := 0; i < len(program.nodes); i += 1 {
			#partial switch _ in &program.nodes[i] {
			case Empty:
				program.nodes[i] = Pair{left, right}
			}
		}
		append(&program.nodes, Pair{left, right})
	}

	for pair in def.redexes {
		link(
			program,
			{
				adjust_addr(pair.left, offset_vars, offset_node),
				adjust_addr(pair.right, offset_vars, offset_node),
			},
		)
	}
	link(program, {adjust_addr(def.root, offset_vars, offset_node), b})
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
					switch node in node {
					case Empty:
					case Pair:
						fmt.wprintfln(
							fi.writer,
							"\t\t%4d:\t%v\t,\t%v",
							index,
							node.left,
							node.right,
						)
					}
				}

				fmt.wprintfln(fi.writer, "\tRedexes:")

				for index in 0 ..< queue.len(m.redexes) {
					redex := queue.get(&m.redexes, index)
					fmt.wprintfln(fi.writer, "\t\t%4d:\t%v\t~\t%v", index, redex.left, redex.right)
				}

				fmt.wprintfln(fi.writer, "\tVars:")

				for var, index in m.vars {
					if index == 0 {
						fmt.wprintf(fi.writer, "\t\tROOT:\t")
					} else {
						fmt.wprintf(fi.writer, "\t\t%4d:\t", index)
					}
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
