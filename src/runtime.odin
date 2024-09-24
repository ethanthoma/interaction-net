package main

import "core:container/queue"
import "core:fmt"
import "core:strings"
import "core:time"

// address of ROOT var
ROOT: u32 : 0
// address of MAIN ref
MAIN: u32 : 0

Program :: struct {
	nodes:   [dynamic]Maybe(Pair),
	redexes: queue.Queue(Pair),
	vars:    [dynamic]Maybe(Port),
	nums:    [dynamic]u32,
}

@(private = "file")
Context :: struct {
	book:                     ^Book,
	interactions:             int,
	accumulated_interactions: int,
	stopwatch:                time.Stopwatch,
}

run :: proc(book: ^Book) {
	ctx := Context{book, 0, 0, time.Stopwatch{}}
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
	queue.push_front(&program.redexes, Pair{{tag = .REF, data = MAIN}, {tag = .VAR, data = ROOT}})

	time.stopwatch_start(&ctx.stopwatch)

	for {
		redex := queue.pop_front_safe(&program.redexes) or_break
		interact(&program, redex)
	}

	time.stopwatch_stop(&ctx.stopwatch)

	sb := strings.builder_make()

	recursive_print(&program, {tag = .VAR, data = ROOT}, &sb)

	result := strings.to_string(sb)
	defer delete(result)

	fmt.printfln("Result:\t%v", result)
	print_time()
}

@(private = "file")
print_time :: proc() {
	timer := (cast(^Context)context.user_ptr).stopwatch
	interactions := (cast(^Context)context.user_ptr).interactions
	duration := time.stopwatch_duration(timer)
	seconds := time.duration_seconds(duration)

	fmt.printfln("Interactions:\t%d", interactions)
	fmt.printfln("Time:\t%v", duration)
	fmt.printfln("MIps:\t%f", (f64(interactions) / 1_000_000) / seconds)
}

@(private = "file")
recursive_print :: proc(program: ^Program, port: Port, sb: ^strings.Builder) {
	#partial switch port.tag {
	case .ERA:
		fmt.sbprint(sb, "ERA()")
	case .REF:
		addr := get_data(port).(Ref_Data).addr
		name := (cast(^Context)context.user_ptr).book.names[addr]
		fmt.sbprintf(sb, "@%v", name)
	case .VAR:
		got := enter(program, port)
		if got != port {
			recursive_print(program, got, sb)
		} else {
			addr := get_data(port).(Var_Data).addr
			fmt.sbprintf(sb, "v%d", addr)
		}
	case .NUM:
		type := get_data(port).(Num_Data).type
		addr := get_data(port).(Num_Data).addr
		value := program.nums[addr]
		switch type {
		case .Uint:
			fmt.sbprintf(sb, "%v", transmute(u32)value)
		case .Int:
			fmt.sbprintf(sb, "%v", transmute(i32)value)
		case .Float:
			fmt.sbprintf(sb, "%v", transmute(f32)value)
		}
	case .OPE:
		type := get_data(port).(Op_Data).type
		addr := get_data(port).(Op_Data).addr

		#partial switch type {
		case .Add:
			fmt.sbprint(sb, "+(")
		case .Sub:
			fmt.sbprint(sb, "-(")
		case:
			panic("NOT SUPPORTED OP")
		}

		pair := program.nodes[addr]
		recursive_print(program, pair.?.left, sb)
		fmt.sbprint(sb, ", ")
		recursive_print(program, pair.?.right, sb)
		fmt.sbprint(sb, ")")
	case:
		#partial switch port.tag {
		case .CON:
			fmt.sbprint(sb, "CON(")
		case .DUP:
			fmt.sbprint(sb, "DUP(")
		case .SWI:
			fmt.sbprint(sb, "SWI(")
		}
		addr := get_data(port).(Node_Data).addr
		pair := program.nodes[addr]
		recursive_print(program, pair.?.left, sb)
		fmt.sbprint(sb, ", ")
		recursive_print(program, pair.?.right, sb)
		fmt.sbprint(sb, ")")
	}
}

@(private = "file")
interact :: proc(program: ^Program, redex: Pair) {
	a, b := redex.left, redex.right
	ctx := cast(^Context)context.user_ptr

	if a.tag < b.tag do a, b = b, a

	tags := struct {
		tag_a: Tag,
		tag_b: Tag,
	}({a.tag, b.tag})
	switch tags {
	case {.DUP, .CON}, {.SWI, .DUP}, {.OPE, .DUP}:
		commute(program, redex)
	case {.CON, .ERA},
	     {.DUP, .ERA},
	     {.DUP, .REF},
	     {.CON, .NUM},
	     {.DUP, .NUM},
	     {.SWI, .ERA},
	     {.OPE, .ERA}:
		erase(program, redex)
	case {.CON, .CON}, {.DUP, .DUP}, {.SWI, .SWI}, {.OPE, .OPE}:
		annihilate(program, redex)
	case {.ERA, .ERA}, {.REF, .REF}, {.REF, .ERA}, {.NUM, .ERA}, {.NUM, .REF}, {.NUM, .NUM}:
		void(program, redex)
	case {.CON, .REF}, {.SWI, .REF}, {.OPE, .REF}:
		call(program, redex)
	case {.SWI, .CON}, {.OPE, .CON}:
		apply(program, redex)
	case {.SWI, .NUM}:
		cond(program, redex)
	case {.OPE, .NUM}:
		operate(program, redex)
	case {.SWI, .OPE}:
		fmt.printfln("SWI:OPE")
	case:
		if a.tag == .REF && b == {tag = .VAR, data = ROOT} do call(program, redex)
		else if a.tag == .VAR || b.tag == .VAR {
			link(program, redex)
			ctx.interactions -= 1
		} else do fmt.eprintfln("Missing rule for %v:%v", a.tag, b.tag)
	}

	ctx.interactions += 1
	ctx.accumulated_interactions += 1

	if ctx.accumulated_interactions >= 10_000 {
		print_time()

		for ctx.accumulated_interactions >= 10_000 {
			ctx.accumulated_interactions -= 10_000
		}
	}
}

@(private = "file")
commute :: proc(program: ^Program, redex: Pair) {
	con, dup := redex.left, redex.right
	if con.tag == .DUP do con, dup = dup, con

	con_addr: int

	#partial switch con.tag {
	case .OPE:
		con_addr = get_data(con).(Op_Data).addr
	case .CON, .SWI:
		con_addr = get_data(con).(Node_Data).addr
	case:
		panic("Commute failed")
	}

	dup_addr := get_data(dup).(Node_Data).addr

	con_node := program.nodes[con_addr].(Pair)
	dup_node := program.nodes[dup_addr].(Pair)

	x1 := create_var(program)
	x2 := create_var(program)
	x3 := create_var(program)
	x4 := create_var(program)

	node_1 := create_node(program, con.tag, {{tag = .VAR, data = x1}, {tag = .VAR, data = x2}})
	node_2 := create_node(program, con.tag, {{tag = .VAR, data = x3}, {tag = .VAR, data = x4}})
	node_3 := create_node(program, dup.tag, {{tag = .VAR, data = x1}, {tag = .VAR, data = x3}})
	node_4 := create_node(program, dup.tag, {{tag = .VAR, data = x2}, {tag = .VAR, data = x4}})

	link(program, {node_1, dup_node.left})
	link(program, {node_2, dup_node.right})
	link(program, {node_3, con_node.left})
	link(program, {node_4, con_node.right})

	delete_node(program, con_addr)
	delete_node(program, dup_addr)
}

@(private = "file")
create_var :: proc(program: ^Program) -> u32 {
	addr := len(program.vars)
	append(&program.vars, nil)
	return transmute(u32)Var_Data{addr = addr}
}

@(private = "file")
create_node :: proc(program: ^Program, kind: Tag, pair: Pair) -> (port: Port) {
	port.tag = kind

	loop: for i := 0; i < len(program.nodes); i += 1 {
		#partial switch _ in &program.nodes[i] {
		case nil:
			program.nodes[i] = pair
			port.data = transmute(u32)Node_Data{addr = i}
			return port
		}
	}

	port.data = transmute(u32)Node_Data{addr = len(program.nodes)}
	append(&program.nodes, pair)
	return port
}

@(private = "file")
create_op :: proc(program: ^Program, type: Op_Type, pair: Pair) -> (port: Port) {
	port.tag = .OPE

	loop: for i := 0; i < len(program.nodes); i += 1 {
		#partial switch _ in &program.nodes[i] {
		case nil:
			program.nodes[i] = pair
			port.data = transmute(u32)Op_Data{type = type, addr = i}
			return port
		}
	}

	port.data = transmute(u32)Op_Data{type = type, addr = len(program.nodes)}
	append(&program.nodes, pair)
	return port
}

@(private = "file")
delete_node :: proc(program: ^Program, addr: int) {
	program.nodes[addr] = nil
}

// TODO: Num needs to be copied so we can erase them, rn nums stay forever
@(private = "file")
erase :: proc(program: ^Program, redex: Pair) {
	a, b := redex.left, redex.right

	#partial switch a.tag {
	case .ERA, .REF, .NUM:
		a, b = b, a
	}

	// a is CON or DUP or SWI or OPE
	// b is ERA or REF or NUM
	addr: int
	#partial switch a.tag {
	case .CON, .DUP, .SWI:
		addr = get_data(a).(Node_Data).addr
	case .OPE:
		addr = get_data(a).(Op_Data).addr
	}
	node := program.nodes[addr].(Pair)

	delete_node(program, addr)

	link(program, {b, node.left})
	link(program, {b, node.right})
}

@(private = "file")
annihilate :: proc(program: ^Program, redex: Pair) {
	a, b := redex.left, redex.right

	address_a: int
	address_b: int

	#partial switch a.tag {
	case .OPE:
		address_a = get_data(a).(Op_Data).addr
		address_b = get_data(b).(Op_Data).addr
	case .CON, .DUP, .SWI:
		address_a = get_data(a).(Node_Data).addr
		address_b = get_data(b).(Node_Data).addr
	case:
		panic("Commute failed")
	}

	node_a := program.nodes[address_a].(Pair)
	node_b := program.nodes[address_b].(Pair)

	#partial switch a.tag {
	case .CON:
		link(program, {node_a.left, node_b.right})
		link(program, {node_a.right, node_b.left})
	case .DUP, .SWI, .OPE:
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

		var_addr := get_data(a).(Var_Data).addr

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
		addr := get_data(var).(Var_Data).addr
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
	addr: int,
	new_port: Maybe(Port),
) -> (
	old_port: Maybe(Port),
) {
	old_port = program.vars[addr]
	program.vars[addr] = new_port
	return old_port
}

@(private = "file")
vars_take :: proc(program: ^Program, addr: int) {
	vars_exchange(program, addr, nil)
}

@(private = "file")
call :: proc(program: ^Program, redex: Pair) {
	a, b := redex.left, redex.right

	if a.tag != .REF do a, b = b, a

	addr := get_data(a).(Ref_Data).addr

	def := (cast(^Context)context.user_ptr).book.defs[addr]

	offsets := [?]int{len(program.vars), len(program.nodes), len(program.nums)}
	adjust_addr := proc(port: Port, offsets: [3]int) -> Port {
		port := port

		switch port.tag {
		case .VAR:
			port.data = transmute(u32)Var_Data{addr = offsets[0] + get_data(port).(Var_Data).addr}
		case .CON, .DUP, .SWI:
			port.data =
			transmute(u32)Node_Data{addr = offsets[1] + get_data(port).(Node_Data).addr}
		case .NUM:
			port.data =
			transmute(u32)Num_Data {
				type = get_data(port).(Num_Data).type,
				addr = offsets[2] + get_data(port).(Num_Data).addr,
			}
		case .ERA, .REF:
		case .OPE:
			port.data =
			transmute(u32)Op_Data {
				type = get_data(port).(Op_Data).type,
				addr = offsets[1] + get_data(port).(Op_Data).addr,
			}
		}

		return port
	}

	for var in 0 ..< def.vars {
		create_var(program)
	}

	// create_node fills in gaps
	// we use a constant offset so we have to append only
	// this means the that the node buffer only grows, never shrinks
	// also makes it hella slow for long operations
	// we should probably have a free list instead
	for node in def.nodes {
		left := adjust_addr(node.left, offsets)
		right := adjust_addr(node.right, offsets)
		append(&program.nodes, Pair{left, right})
	}

	for pair in def.redexes {
		link(program, {adjust_addr(pair.left, offsets), adjust_addr(pair.right, offsets)})
	}

	link(program, {adjust_addr(def.root, offsets), b})

	for num in def.numbers {
		append(&program.nums, num)
	}
}

@(private = "file")
apply :: proc(program: ^Program, redex: Pair) {
	swi_or_ope, con := redex.left, redex.right

	if con.tag != .CON do swi_or_ope, con = con, swi_or_ope

	addr_con := get_data(con).(Node_Data).addr
	pair_con := program.nodes[addr_con].(Pair)

	x1 := create_var(program)
	x2 := create_var(program)
	x3 := create_var(program)
	x4 := create_var(program)

	node_dup := create_node(program, .DUP, {{tag = .VAR, data = x1}, {tag = .VAR, data = x2}})
	node_con := create_node(program, .CON, {{tag = .VAR, data = x3}, {tag = .VAR, data = x4}})

	link(program, {node_dup, pair_con.left})
	link(program, {node_con, pair_con.right})

	#partial switch swi_or_ope.tag {
	case .SWI:
		swi := swi_or_ope

		addr_swi := get_data(swi).(Node_Data).addr
		pair_swi := program.nodes[addr_swi].(Pair)

		node_swi1 := create_node(
			program,
			swi.tag,
			{{tag = .VAR, data = x1}, {tag = .VAR, data = x3}},
		)
		node_swi2 := create_node(
			program,
			swi.tag,
			{{tag = .VAR, data = x2}, {tag = .VAR, data = x4}},
		)

		link(program, {node_swi1, pair_swi.left})
		link(program, {node_swi2, pair_swi.right})

		delete_node(program, addr_swi)
	case .OPE:
		ope := swi_or_ope
		type := get_data(ope).(Op_Data).type

		addr_ope := get_data(ope).(Op_Data).addr
		pair_ope := program.nodes[addr_ope].(Pair)

		node_ope1 := create_op(program, type, {{tag = .VAR, data = x1}, {tag = .VAR, data = x3}})
		node_ope2 := create_op(program, type, {{tag = .VAR, data = x2}, {tag = .VAR, data = x4}})

		link(program, {node_ope1, pair_ope.left})
		link(program, {node_ope2, pair_ope.right})

		delete_node(program, addr_ope)
	}

	delete_node(program, addr_con)
}

@(private = "file")
cond :: proc(program: ^Program, redex: Pair) {
	swi, num := redex.left, redex.right

	if swi.tag != .SWI do swi, num = num, swi

	addr_swi := get_data(swi).(Node_Data).addr
	pair := program.nodes[addr_swi].(Pair)

	type := get_data(num).(Num_Data).type
	addr_num := get_data(num).(Num_Data).addr
	value := program.nums[addr_num]

	is_zero: bool
	switch type {
	case .Uint:
		is_zero = transmute(u32)value == 0
		value = transmute(u32)((transmute(u32)value) - 1)
	case .Int:
		is_zero = transmute(i32)value == 0
		value = transmute(u32)((transmute(i32)value) - 1)
	case .Float:
		is_zero = transmute(f32)value == 0
		value = transmute(u32)((transmute(f32)value) - 1)
	}

	if is_zero {
		node_con := create_node(
			program,
			.CON,
			{pair.right, {tag = .ERA, data = transmute(u32)Empty{}}},
		)

		link(program, {pair.left, node_con})
	} else {
		num_new := Num_Data {
			type = type,
			addr = len(program.nums),
		}
		append(&program.nums, value)

		node_con1 := create_node(
			program,
			.CON,
			{{tag = .NUM, data = transmute(u32)num_new}, pair.right},
		)
		node_con2 := create_node(
			program,
			.CON,
			{{tag = .ERA, data = transmute(u32)Empty{}}, node_con1},
		)

		link(program, {pair.left, node_con2})
	}
}

// TODO: handle case where left is not a num
@(private = "file")
operate :: proc(program: ^Program, redex: Pair) {
	op, num := redex.left, redex.right

	if op.tag != .OPE do op, num = num, op

	type := get_data(op).(Op_Data).type
	addr := get_data(op).(Op_Data).addr

	pair := program.nodes[addr].(Pair)

	// swap rule: # ~ $(a, b) -> a ~ $(#, b)
	if pair.left.tag != .NUM {
		node_op := create_op(program, type, {num, pair.right})
		link(program, {pair.left, node_op})
	} else {
		left, right := num, pair.left

		value_left, value_right, result_type := get_num_values(program, left, right)

		result: u32
		#partial switch type {
		case .Add:
			result = add(value_left, value_right)
		case .Sub:
			result = sub(value_left, value_right)
		case:
			panic("Unsupported operation")
		}

		num_new := Num_Data {
			type = result_type,
			addr = len(program.nums),
		}
		append(&program.nums, result)

		link(program, {{tag = .NUM, data = transmute(u32)num_new}, pair.right})
	}
}

@(private = "file")
apply_operation :: proc(program: ^Program) {

}

@(private = "file")
Data_Values :: union {
	u32,
	i32,
	f32,
}

@(private = "file")
get_num_values :: proc(program: ^Program, a, b: Port) -> (Data_Values, Data_Values, Num_Type) {
	a, b := a, b

	type_a := get_data(a).(Num_Data).type
	type_b := get_data(b).(Num_Data).type

	if type_a < type_b {
		a, b = b, a
		type_a, type_b = type_b, type_a
	}

	addr_a := get_data(a).(Num_Data).addr
	value_a := program.nums[addr_a]

	addr_b := get_data(b).(Num_Data).addr
	value_b := program.nums[addr_b]

	switch struct {
		a, b: Num_Type,
	}({type_a, type_b}) {
	case {.Float, .Float}:
		return transmute(f32)value_a, transmute(f32)value_b, .Float
	case {.Float, .Int}:
		return transmute(f32)value_a, cast(f32)transmute(i32)value_b, .Float
	case {.Float, .Uint}:
		return transmute(f32)value_a, cast(f32)transmute(u32)value_b, .Float
	case {.Int, .Int}:
		return transmute(i32)value_a, transmute(i32)value_b, .Int
	case {.Int, .Uint}:
		return transmute(i32)value_a, cast(i32)transmute(u32)value_b, .Int
	case {.Uint, .Uint}:
		return transmute(u32)value_a, transmute(u32)value_b, .Uint
	}

	panic("Invalid type")
}

@(private = "file")
add :: proc(a, b: Data_Values) -> u32 {
	switch v in a {
	case f32:
		return transmute(u32)(v + b.(f32))
	case i32:
		return transmute(u32)(v + b.(i32))
	case u32:
		return transmute(u32)(v + b.(u32))
	}
	unreachable()
}

@(private = "file")
sub :: proc(a, b: Data_Values) -> u32 {
	switch v in a {
	case f32:
		return transmute(u32)(v - b.(f32))
	case i32:
		return transmute(u32)(v - b.(i32))
	case u32:
		return transmute(u32)(v - b.(u32))
	}
	unreachable()
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

				fmt.wprintfln(fi.writer, "\tNums:")

				for num, index in m.nums {
					fmt.wprintfln(fi.writer, "\t\t%4d:\t%v", index, num)
				}

				fmt.wprintf(fi.writer, "}}")
			case:
				return false
			}

			return true
		},
	)
}
