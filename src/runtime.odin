package main

import "core:container/queue"
import "core:fmt"
import "core:strings"
import "core:time"

// address of ROOT var
ROOT :: Var_Address(0)
// address of MAIN ref
MAIN :: Ref_Address(0)

Program :: struct {
	nodes:   [dynamic]Maybe(Pair),
	redexes: queue.Queue(Pair),
	vars:    [dynamic]Maybe(Port),
	nums:    [dynamic]u32,
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
		nodes = make([dynamic]Maybe(Pair)),
		vars  = make([dynamic]Maybe(Port)),
		nums  = make([dynamic]u32),
	}
	queue.init(&program.redexes)

	defer delete(program.nodes)
	defer delete(program.vars)
	defer delete(program.nums)
	defer queue.destroy(&program.redexes)

	assign_at(&program.vars, int(ROOT), nil)
	queue.push_front(&program.redexes, Pair{{.REF, MAIN}, {.VAR, ROOT}})

	timer := time.Stopwatch{}

	time.stopwatch_start(&timer)

	for {
		redex := queue.pop_front_safe(&program.redexes) or_break
		interact(&program, redex)
	}

	time.stopwatch_stop(&timer)

	result := make_result(&program)
	defer delete_result(result)

	fmt.printfln("Result:\t%v", result)
	fmt.printfln("Interactions:\t%d", ctx.interactions)
	fmt.printfln("Time:\t%v", time.stopwatch_duration(timer))
	fmt.printfln(
		"MIps:\t%f",
		(f64(ctx.interactions) / 1_000_000) /
		time.duration_seconds(time.stopwatch_duration(timer)),
	)
}

make_result :: proc(program: ^Program) -> string {
	sb := strings.builder_make()

	recursive_print(program, {.VAR, ROOT}, &sb)

	return strings.to_string(sb)
}

delete_result :: proc(result: string) {
	delete(result)
}

@(private = "file")
recursive_print :: proc(program: ^Program, port: Port, sb: ^strings.Builder) {
	switch port.tag {
	case .ERA:
		fmt.sbprint(sb, "ERA()")
	case .REF:
		name := (cast(^Context)context.user_ptr).book.names[port.data.(Ref_Address)]
		fmt.sbprintf(sb, "@%v", name)
	case .VAR:
		got := enter(program, port)
		if got != port {
			recursive_print(program, got, sb)
		} else {
			fmt.sbprintf(sb, "v%d", port.data.(Var_Address))
		}
	case .CON:
		pair := program.nodes[port.data.(Node_Address)]
		fmt.sbprint(sb, "CON(")
		recursive_print(program, pair.?.left, sb)
		fmt.sbprint(sb, ", ")
		recursive_print(program, pair.?.right, sb)
		fmt.sbprint(sb, ")")
	case .DUP:
		pair := program.nodes[port.data.(Node_Address)]
		fmt.sbprint(sb, "DUP(")
		recursive_print(program, pair.?.left, sb)
		fmt.sbprint(sb, ", ")
		recursive_print(program, pair.?.right, sb)
		fmt.sbprint(sb, ")")
	case .NUM:
		type := port.data.(Num_Address) & 0x0003
		addr := (port.data.(Num_Address) >> 2) & 0x3FFF
		value := program.nums[addr]
		switch type {
		case 0:
			// Uint
			fmt.sbprintf(sb, "%v", transmute(u32)value)
		case 1:
			// Int
			fmt.sbprintf(sb, "%v", transmute(i32)value)
		case 2:
			// Float
			fmt.sbprintf(sb, "%v", transmute(f32)value)
		}
	}
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
	case {.CON, .ERA}, {.DUP, .ERA}, {.DUP, .REF}, {.CON, .NUM}, {.DUP, .NUM}:
		erase(program, redex)
	case {.CON, .CON}, {.DUP, .DUP}:
		annihilate(program, redex)
	case {.ERA, .ERA}, {.REF, .REF}, {.REF, .ERA}, {.NUM, .ERA}, {.NUM, .REF}, {.NUM, .NUM}:
		void(program, redex)
	case {.CON, .REF}:
		call(program, redex)
	case:
		if a.tag == .REF && b == {.VAR, ROOT} do call(program, redex)
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
	append(&program.vars, nil)
	return Var_Address(addr)
}

@(private = "file")
create_node :: proc(program: ^Program, kind: Term_Kind, var_left, var_right: Var_Address) -> Port {
	left := Port{.VAR, var_left}
	right := Port{.VAR, var_right}
	for i := 0; i < len(program.nodes); i += 1 {
		#partial switch _ in &program.nodes[i] {
		case nil:
			program.nodes[i] = Pair{left, right}
			return Port{tag = kind, data = Node_Address(i)}
		}
	}
	append(&program.nodes, Pair{left, right})
	return Port{tag = kind, data = Node_Address(len(program.nodes) - 1)}
}

@(private = "file")
delete_node :: proc(program: ^Program, address: Node_Address) {
	program.nodes[address] = nil
}

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

	link(program, {a, node.left})
	link(program, {a, node.right})
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
		case nil:
			break loop
		}
	}
}

@(private = "file")
enter :: proc(program: ^Program, var: Port) -> Port {
	var := var

	loop: for var.tag == .VAR {
		addr := var.data.(Var_Address)
		val := vars_exchange(program, addr, nil)
		switch val in val {
		case nil:
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
	new_port: Maybe(Port),
) -> (
	old_port: Maybe(Port),
) {
	old_port = program.vars[addr]
	program.vars[addr] = new_port
	return old_port
}

@(private = "file")
vars_take :: proc(program: ^Program, addr: Var_Address) {
	vars_exchange(program, addr, nil)
}

@(private = "file")
call :: proc(program: ^Program, redex: Pair) {
	a, b := redex.left, redex.right

	if a.tag != .REF do a, b = b, a

	addr := a.data.(Ref_Address)

	def := (cast(^Context)context.user_ptr).book.defs[addr]


	offsets := [?]int{len(program.vars), len(program.nodes), len(program.nums)}
	adjust_addr := proc(port: Port, offsets: [3]int) -> Port {
		port := port

		#partial switch port.tag {
		case .VAR:
			port.data = Var_Address(offsets[0] + int(port.data.(Var_Address)))
		case .CON, .DUP:
			port.data = Node_Address(offsets[1] + int(port.data.(Node_Address)))
		case .NUM:
			type: u32 = u32(port.data.(Num_Address)) & 0x0003
			addr: u32 = (u32(port.data.(Num_Address)) >> 2) & 0x3FFF
			port.data = Num_Address(((u32(offsets[2]) + addr) << 2) | type)
		}

		return port
	}

	for var in 0 ..< def.vars {
		create_var(program)
	}

	// create_node fills in gaps
	// we use a constant offset so we have to append only
	// this means the that the node buffer only grows, never shrinks
	for node in def.nodes {
		left := node.left
		right := node.right


		left = adjust_addr(left, offsets)
		right = adjust_addr(right, offsets)

		for i := 0; i < len(program.nodes); i += 1 {
			#partial switch _ in &program.nodes[i] {
			case nil:
				program.nodes[i] = Pair{left, right}
			}
		}
		append(&program.nodes, Pair{left, right})
	}

	for pair in def.redexes {
		link(program, {adjust_addr(pair.left, offsets), adjust_addr(pair.right, offsets)})
	}

	for num in def.numbers {
		append(&program.nums, num)
	}

	link(program, {adjust_addr(def.root, offsets), b})
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
					case nil:
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
					#partial switch var in var {
					case Port:
						if index == int(ROOT) {
							fmt.wprintf(fi.writer, "\t\tROOT:\t")
						} else {
							fmt.wprintf(fi.writer, "\t\t%4d:\t", index)
						}
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
