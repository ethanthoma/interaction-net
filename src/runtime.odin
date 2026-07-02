package main

import "base:runtime"
import "core:fmt"
import "core:os"
import "core:strconv"
import "core:strings"
import "core:sync"
import "core:thread"
import "core:time"
import "shared:arena"
import "shared:deque"
import "shared:queue"

// address of ROOT var
ROOT: u32 : 0
// address of MAIN ref
MAIN: u32 : 0

VARS_EMPTY: u32 : max(u32)

PROFILE :: #config(PROFILE, false)

Rule :: enum u8 {
	Commute,
	Erase,
	Annihilate,
	Void,
	Call,
	Apply,
	Cond,
	Operate,
}

Num_Event :: enum u8 {
	Read,
	Alloc,
	Free,
}

// Where a worker's take_work found its next redex, or Miss when it found none
// and fell into backoff. Chain counts redexes consumed without touching the
// deque (tail-chained from the previous interaction). Confirms whether the
// runtime anti-scales because idle workers are starved and spinning.
Coord_Event :: enum u8 {
	Own,
	Steal,
	Global,
	Miss,
	Overflow,
	Chain,
}

when PROFILE {
	@(private = "file")
	prof_counts: [Rule]int

	@(private = "file")
	prof_num_counts: [Num_Event]int

	@(private = "file")
	prof_coord_total: [Coord_Event]int

	@(private = "file")
	prof_count :: proc(rule: Rule) {
		sync.atomic_add(&prof_counts[rule], 1)
	}

	@(private = "file")
	prof_num :: proc(event: Num_Event) {
		sync.atomic_add(&prof_num_counts[event], 1)
	}

	@(private = "file")
	prof_report :: proc(program: ^Program) {
		total := 0
		for count in prof_counts do total += count
		for count, rule in prof_counts {
			share := 100 * f64(count) / f64(max(total, 1))
			fmt.printfln("Rule %-11v %d  (%.1f%%)", rule, count, share)
		}

		num_touches := 0
		for count in prof_num_counts do num_touches += count
		slots := arena.high_water(&program.nums)
		fmt.printfln("Nums %-11v %d  (%.2f/interaction)", "touches", num_touches, f64(num_touches) / f64(max(total, 1)))
		for count, event in prof_num_counts {
			fmt.printfln("Nums %-11v %d", event, count)
		}
		slot_bytes := size_of(arena.Slot(u32, align_of(u32)))
		fmt.printfln("Nums %-11v %d values, %d bytes physical (%dB slots)", "peak", slots, slots * slot_bytes, slot_bytes)

		takes := 0
		for count in prof_coord_total do takes += count
		for count, event in prof_coord_total {
			share := 100 * f64(count) / f64(max(takes, 1))
			fmt.printfln("Work %-11v %d  (%.1f%%)", event, count, share)
		}
	}
}

Program :: struct {
	nodes:       arena.Arena(Pair, align_of(Pair)),
	redexes:     queue.Queue(Pair),
	vars:        arena.Arena(u32, align_of(u32)),
	nums:        arena.Arena(u32, align_of(u32)),
	outstanding: int,
}

@(private = "file")
Context :: struct {
	book:         ^Book,
	interactions: int,
	stopwatch:    time.Stopwatch,
	workers:      []Worker,
}

DEQUE_CAP :: 1 << 16

run :: proc(book: ^Book) {
	ctx := Context{book, 0, time.Stopwatch{}, nil}

	NODE_CAP :: 1 << 23
	VAR_CAP :: 1 << 24
	NUM_CAP :: 1 << 22
	REDEX_CAP :: 1 << 16

	program: Program
	arena.init(&program.nodes, NODE_CAP)
	arena.init(&program.vars, VAR_CAP)
	arena.init(&program.nums, NUM_CAP)
	queue.init(&program.redexes, REDEX_CAP)

	defer arena.destroy(&program.nodes)
	defer arena.destroy(&program.nums)
	defer arena.destroy(&program.vars)
	defer queue.destroy(&program.redexes)

	seed_root(&program)
	seed_redex(&program, Pair{make_port(.REF, MAIN), make_port(.VAR, ROOT)})

	num_workers := max(os.get_processor_core_count(), 1)
	if env := os.get_env("INIO_WORKERS", context.temp_allocator); env != "" {
		if n, ok := strconv.parse_int(env); ok && n > 0 {
			num_workers = n
		}
	}

	time.stopwatch_start(&ctx.stopwatch)

	normalize(&program, &ctx, num_workers)

	time.stopwatch_stop(&ctx.stopwatch)

	print_time(&ctx)

	when PROFILE do prof_report(&program)

	serialize_worker := Worker {
		program = &program,
	}
	context.user_ptr = &serialize_worker
	defer arena.cache_destroy(&serialize_worker.vars)

	fmt.printfln("Result:\t%v", serialize(&program, book))
}

@(private = "file")
seed_redex :: proc(program: ^Program, pair: Pair) {
	sync.atomic_add(&program.outstanding, 1)
	queue.push(&program.redexes, pair)
}

@(private = "file")
seed_root :: proc(program: ^Program) {
	c: arena.Cache
	arena.alloc(&program.vars, &c, VARS_EMPTY)
	arena.cache_destroy(&c)
}

// The first redex produced by an interaction is tail-chained: parked in
// worker.next and reduced immediately after, without touching the deque. It
// inherits the consumed redex's outstanding count, so no atomics either; the
// worker_loop decrements once when the chain dies.
@(private = "file")
push_redex :: proc(program: ^Program, pair: Pair) {
	worker := cast(^Worker)context.user_ptr
	if !worker.has_next {
		worker.has_next = true
		worker.next = pair
		return
	}
	sync.atomic_add(&program.outstanding, 1)
	if !deque.push(&worker.deques[worker.id], pair) {
		when PROFILE do worker.coord[.Overflow] += 1
		queue.push(&program.redexes, pair)
	}
}

@(private = "file")
Worker :: struct #align (arena.CACHE_LINE_SIZE) {
	program:      ^Program,
	ctx:          ^Context,
	deques:       []deque.Deque(Pair),
	id:           int,
	interactions: int,
	next:         Pair,
	has_next:     bool,
	coord:        [Coord_Event]int,
	nodes:        arena.Cache,
	vars:         arena.Cache,
	nums:         arena.Cache,
}

@(private = "file")
normalize :: proc(program: ^Program, ctx: ^Context, num_workers: int) {
	deques := make([]deque.Deque(Pair), num_workers)
	for &d in deques do deque.init(&d, DEQUE_CAP)
	defer {
		for &d in deques do deque.destroy(&d)
		delete(deques)
	}

	workers := make([]Worker, num_workers)
	threads := make([]^thread.Thread, num_workers)
	defer delete(workers)
	defer delete(threads)

	ctx.workers = workers

	for &worker, id in workers {
		worker = Worker {
			program = program,
			ctx     = ctx,
			deques  = deques,
			id      = id,
		}
		threads[id] = thread.create_and_start_with_poly_data(&worker, worker_loop)
	}

	for t in threads do thread.join(t)

	ctx.interactions = 0
	for &worker in workers do ctx.interactions += worker.interactions
	ctx.workers = nil

	when PROFILE {
		for &worker in workers {
			for count, event in worker.coord do prof_coord_total[event] += count
		}
	}

	for &worker in workers {
		arena.cache_destroy(&worker.nodes)
		arena.cache_destroy(&worker.vars)
		arena.cache_destroy(&worker.nums)
	}
	for t in threads do thread.destroy(t)
}

SPIN_LIMIT :: 8
YIELD_LIMIT :: 16

TICK_INTERVAL :: 1 << 16

@(private = "file")
worker_loop :: proc(worker: ^Worker) {
	context.user_ptr = worker
	own := &worker.deques[worker.id]
	next_tick := 0
	next_tick_check := TICK_INTERVAL
	idle := 0

	for {
		redex, ok := take_work(worker, own)
		if !ok {
			// outstanding == 0 is a stable terminal state, only reachable once
			// every worker is quiescent, so only the deep-idle path needs to load
			// the shared counter. Checking it on every busy-spin is what makes the
			// runtime anti-scale (idle workers ping-pong the line against active ones).
			if idle >= YIELD_LIMIT && sync.atomic_load(&worker.program.outstanding) == 0 {
				return
			}
			backoff(idle)
			idle += 1
			continue
		}
		idle = 0

		for {
			interact(worker.program, redex)

			if worker.id == 0 && worker.interactions >= next_tick_check {
				next_tick_check = worker.interactions + TICK_INTERVAL
				seconds := int(time.duration_seconds(time.stopwatch_duration(worker.ctx.stopwatch)))
				if seconds >= next_tick {
					next_tick = seconds + 1
					print_time(worker.ctx)
				}
			}

			if !worker.has_next do break
			worker.has_next = false
			redex = worker.next
			when PROFILE do worker.coord[.Chain] += 1
		}
		sync.atomic_sub(&worker.program.outstanding, 1)
	}
}

@(private = "file")
backoff :: proc(idle: int) {
	if idle < SPIN_LIMIT {
		for _ in 0 ..< 1 << uint(idle) do sync.cpu_relax()
	} else if idle < YIELD_LIMIT {
		thread.yield()
	} else {
		time.sleep(100 * time.Microsecond)
	}
}

@(private = "file")
take_work :: proc(worker: ^Worker, own: ^deque.Deque(Pair)) -> (Pair, bool) {
	if redex, ok := deque.pop(own); ok {
		when PROFILE do worker.coord[.Own] += 1
		return redex, true
	}

	n := len(worker.deques)
	for offset in 1 ..< n {
		victim := (worker.id + offset) % n
		if redex, ok := deque.steal(&worker.deques[victim]); ok {
			when PROFILE do worker.coord[.Steal] += 1
			return redex, true
		}
	}

	if redex, ok := queue.pop(&worker.program.redexes); ok {
		when PROFILE do worker.coord[.Global] += 1
		return redex, true
	}

	when PROFILE do worker.coord[.Miss] += 1
	return {}, false
}

evaluate :: proc(book: ^Book, num_workers := 1) -> string {
	ctx := Context{book, 0, time.Stopwatch{}, nil}

	NODE_CAP :: 1 << 16
	REDEX_CAP :: 1 << 14

	program: Program
	arena.init(&program.nodes, NODE_CAP)
	arena.init(&program.nums, NODE_CAP)
	arena.init(&program.vars, NODE_CAP)
	queue.init(&program.redexes, REDEX_CAP)

	defer arena.destroy(&program.nodes)
	defer arena.destroy(&program.nums)
	defer arena.destroy(&program.vars)
	defer queue.destroy(&program.redexes)

	seed_root(&program)
	seed_redex(&program, Pair{make_port(.REF, MAIN), make_port(.VAR, ROOT)})

	normalize(&program, &ctx, num_workers)

	serialize_worker := Worker {
		program = &program,
	}
	context.user_ptr = &serialize_worker
	defer arena.cache_destroy(&serialize_worker.vars)

	return strings.clone(serialize(&program, book))
}

@(private = "file")
total_interactions :: proc(ctx: ^Context) -> int {
	if ctx.workers == nil do return ctx.interactions
	total := 0
	for &worker in ctx.workers do total += worker.interactions
	return total
}

@(private = "file")
print_time :: proc(ctx: ^Context) {
	interactions := total_interactions(ctx)
	duration := time.stopwatch_duration(ctx.stopwatch)
	seconds := time.duration_seconds(duration)

	fmt.printfln("Interactions:\t%d", interactions)
	fmt.printfln("Time:\t%v", duration)
	fmt.printfln("MIps:\t%f", (f64(interactions) / 1_000_000) / seconds)
}

@(private = "file")
interact :: proc(program: ^Program, redex: Pair) {
	a, b := redex.left, redex.right
	worker := cast(^Worker)context.user_ptr

	tag_a, tag_b := port_tag(a), port_tag(b)
	if tag_a < tag_b {
		a, b = b, a
		tag_a, tag_b = tag_b, tag_a
	}

	tags := struct {
		tag_a: Tag,
		tag_b: Tag,
	}({tag_a, tag_b})
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
		panic("undefined interaction: SWI~OPE")
	case:
		if tag_a == .REF && b == make_port(.VAR, ROOT) do call(program, redex)
		else if tag_a == .VAR || tag_b == .VAR {
			link(program, redex)
			worker.interactions -= 1
		} else do fmt.eprintfln("Missing rule for %v:%v", tag_a, tag_b)
	}

	worker.interactions += 1
}

@(private = "file")
commute :: proc(program: ^Program, redex: Pair) {
	when PROFILE do prof_count(.Commute)
	con, dup := redex.left, redex.right
	if port_tag(con) == .DUP do con, dup = dup, con

	con_addr: int
	dup_addr := port_addr(dup)

	x1 := create_var(program)
	x2 := create_var(program)
	x3 := create_var(program)
	x4 := create_var(program)

	node_1, node_2: Port
	#partial switch port_tag(con) {
	case .OPE:
		con_addr = op_addr(con)
		type := op_type(con)
		node_1 = create_op(program, type, {make_port(.VAR, x1), make_port(.VAR, x2)})
		node_2 = create_op(program, type, {make_port(.VAR, x3), make_port(.VAR, x4)})
	case .CON, .SWI:
		con_addr = port_addr(con)
		node_1 = create_node(program, port_tag(con), {make_port(.VAR, x1), make_port(.VAR, x2)})
		node_2 = create_node(program, port_tag(con), {make_port(.VAR, x3), make_port(.VAR, x4)})
	case:
		panic("Commute failed")
	}

	con_node := arena.at(&program.nodes, con_addr)^
	dup_node := arena.at(&program.nodes, dup_addr)^

	node_3 := create_node(program, port_tag(dup), {make_port(.VAR, x1), make_port(.VAR, x3)})
	node_4 := create_node(program, port_tag(dup), {make_port(.VAR, x2), make_port(.VAR, x4)})

	link(program, {node_1, dup_node.left})
	link(program, {node_2, dup_node.right})
	link(program, {node_3, con_node.left})
	link(program, {node_4, con_node.right})

	delete_node(program, con_addr)
	delete_node(program, dup_addr)
}

@(private = "file")
create_var :: proc(program: ^Program) -> u32 {
	return u32(alloc_var(program, VARS_EMPTY))
}

@(private = "file")
alloc_var :: proc(program: ^Program, value: u32) -> int {
	worker := cast(^Worker)context.user_ptr
	index, ok := arena.alloc(&program.vars, &worker.vars, value)
	if !ok do panic("var arena full")
	return index
}

@(private = "file")
delete_var :: proc(program: ^Program, addr: int) {
	worker := cast(^Worker)context.user_ptr
	arena.free(&program.vars, &worker.vars, addr)
}

@(private = "file")
create_node :: proc(program: ^Program, kind: Tag, pair: Pair) -> Port {
	return make_port(kind, u32(alloc_node(program, pair)))
}

@(private = "file")
create_op :: proc(program: ^Program, type: Op_Type, pair: Pair) -> Port {
	return make_op_port(type, alloc_node(program, pair))
}

@(private = "file")
alloc_node :: proc(program: ^Program, pair: Pair) -> int {
	worker := cast(^Worker)context.user_ptr
	index, ok := arena.alloc(&program.nodes, &worker.nodes, pair)
	if !ok do panic("node arena full")
	return index
}

@(private = "file")
alloc_num :: proc(program: ^Program, value: u32) -> int {
	when PROFILE do prof_num(.Alloc)
	worker := cast(^Worker)context.user_ptr
	index, ok := arena.alloc(&program.nums, &worker.nums, value)
	if !ok do panic("num arena full")
	return index
}

@(private = "file")
delete_node :: proc(program: ^Program, addr: int) {
	worker := cast(^Worker)context.user_ptr
	arena.free(&program.nodes, &worker.nodes, addr)
}

@(private = "file")
erase :: proc(program: ^Program, redex: Pair) {
	when PROFILE do prof_count(.Erase)
	a, b := redex.left, redex.right

	#partial switch port_tag(a) {
	case .ERA, .REF, .NUM:
		a, b = b, a
	}

	// a is CON or DUP or SWI or OPE
	// b is ERA or REF or NUM
	addr: int
	#partial switch port_tag(a) {
	case .CON, .DUP, .SWI:
		addr = port_addr(a)
	case .OPE:
		addr = op_addr(a)
	}
	node := arena.at(&program.nodes, addr)^

	delete_node(program, addr)

	b_one, b_two: Port
	if port_tag(b) == .NUM {
		b_one = b
		b_two = copy_num(program, b)
	} else {
		b_one, b_two = b, b
	}

	link(program, {b_one, node.left})
	link(program, {b_two, node.right})
}

@(private = "file")
copy_num :: #force_inline proc(program: ^Program, num: Port) -> Port {
	when PROFILE do prof_num(.Read)
	val := arena.at(&program.nums, num_addr(num))^

	return make_num_port(num_type(num), alloc_num(program, val))
}

@(private = "file")
annihilate :: proc(program: ^Program, redex: Pair) {
	when PROFILE do prof_count(.Annihilate)
	a, b := redex.left, redex.right

	address_a: int
	address_b: int

	#partial switch port_tag(a) {
	case .OPE:
		address_a = op_addr(a)
		address_b = op_addr(b)
	case .CON, .DUP, .SWI:
		address_a = port_addr(a)
		address_b = port_addr(b)
	case:
		panic("Commute failed")
	}

	node_a := arena.at(&program.nodes, address_a)^
	node_b := arena.at(&program.nodes, address_b)^

	#partial switch port_tag(a) {
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
void :: proc(program: ^Program, redex: Pair) {
	when PROFILE do prof_count(.Void)
	if port_tag(redex.left) == .NUM do delete_num(program, num_addr(redex.left))
	if port_tag(redex.right) == .NUM do delete_num(program, num_addr(redex.right))
}

@(private = "file")
delete_num :: proc(program: ^Program, addr: int) {
	when PROFILE do prof_num(.Free)
	worker := cast(^Worker)context.user_ptr
	arena.free(&program.nums, &worker.nums, addr)
}

@(private = "file")
link :: proc(program: ^Program, redex: Pair) {
	a, b := redex.left, redex.right

	loop: for {
		if port_tag(a) != .VAR {
			a, b = b, a
		}

		if port_tag(a) != .VAR {
			push_redex(program, Pair{a, b})
			return
		}

		b = enter(program, b)

		var_addr := port_addr(a)

		switch new_a in vars_exchange(program, var_addr, b) {
		case Port:
			delete_var(program, var_addr)
			a = new_a
		case nil:
			break loop
		}
	}
}

enter :: proc(program: ^Program, var: Port) -> Port {
	var := var

	loop: for port_tag(var) == .VAR {
		addr := port_addr(var)
		val := vars_exchange(program, addr, nil)
		switch v in val {
		case nil:
			break loop
		case Port:
			delete_var(program, addr)
			var = v
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
	bits := VARS_EMPTY
	if port, ok := new_port.?; ok do bits = u32(port)

	old := sync.atomic_exchange(arena.at(&program.vars, addr), bits)
	if old == VARS_EMPTY do return nil

	return Port(old)
}

@(private = "file")
call :: proc(program: ^Program, redex: Pair) {
	when PROFILE do prof_count(.Call)
	a, b := redex.left, redex.right

	if port_tag(a) != .REF do a, b = b, a

	addr := port_addr(a)

	def := (cast(^Worker)context.user_ptr).ctx.book.defs[addr]

	var_base, vars_ok := arena.alloc_range(&program.vars, def.vars)
	if !vars_ok do panic("var arena full")
	for i in 0 ..< def.vars {
		arena.at(&program.vars, var_base + i)^ = VARS_EMPTY
	}

	node_base, nodes_ok := arena.alloc_range(&program.nodes, len(def.nodes))
	if !nodes_ok do panic("node arena full")

	num_base, nums_ok := arena.alloc_range(&program.nums, len(def.numbers))
	if !nums_ok do panic("num arena full")
	for value, i in def.numbers {
		when PROFILE do prof_num(.Alloc)
		arena.at(&program.nums, num_base + i)^ = value
	}

	for node, i in def.nodes {
		left := adjust_addr(node.left, var_base, node_base, num_base)
		right := adjust_addr(node.right, var_base, node_base, num_base)
		arena.at(&program.nodes, node_base + i)^ = Pair{left, right}
	}

	for pair in def.redexes {
		link(
			program,
			{
				adjust_addr(pair.left, var_base, node_base, num_base),
				adjust_addr(pair.right, var_base, node_base, num_base),
			},
		)
	}

	link(program, {adjust_addr(def.root, var_base, node_base, num_base), b})
}

// Def terms use def-local indices; instantiation reserves contiguous arena
// ranges, so remapping is a base offset added to the packed addr bits (shifted
// past the tag, and past the type bits for NUM/OPE).
@(private = "file")
adjust_addr :: proc(port: Port, var_base, node_base, num_base: int) -> Port {
	switch port_tag(port) {
	case .VAR:
		return port + Port(u32(var_base) << Tag_Len)
	case .CON, .DUP, .SWI:
		return port + Port(u32(node_base) << Tag_Len)
	case .NUM:
		return port + Port(u32(num_base) << (Tag_Len + Num_Type_Len))
	case .OPE:
		return port + Port(u32(node_base) << (Tag_Len + Op_Type_Len))
	case .ERA, .REF:
		return port
	}

	return port
}

@(private = "file")
apply :: proc(program: ^Program, redex: Pair) {
	when PROFILE do prof_count(.Apply)
	swi_or_ope, con := redex.left, redex.right

	if port_tag(con) != .CON do swi_or_ope, con = con, swi_or_ope

	addr_con := port_addr(con)
	pair_con := arena.at(&program.nodes, addr_con)^

	x1 := create_var(program)
	x2 := create_var(program)
	x3 := create_var(program)
	x4 := create_var(program)

	node_dup := create_node(program, .DUP, {make_port(.VAR, x1), make_port(.VAR, x2)})
	node_con := create_node(program, .CON, {make_port(.VAR, x3), make_port(.VAR, x4)})

	link(program, {node_dup, pair_con.left})
	link(program, {node_con, pair_con.right})

	#partial switch port_tag(swi_or_ope) {
	case .SWI:
		swi := swi_or_ope

		addr_swi := port_addr(swi)
		pair_swi := arena.at(&program.nodes, addr_swi)^

		node_swi1 := create_node(program, .SWI, {make_port(.VAR, x1), make_port(.VAR, x3)})
		node_swi2 := create_node(program, .SWI, {make_port(.VAR, x2), make_port(.VAR, x4)})

		link(program, {node_swi1, pair_swi.left})
		link(program, {node_swi2, pair_swi.right})

		delete_node(program, addr_swi)
	case .OPE:
		ope := swi_or_ope
		type := op_type(ope)

		addr_ope := op_addr(ope)
		pair_ope := arena.at(&program.nodes, addr_ope)^

		node_ope1 := create_op(program, type, {make_port(.VAR, x1), make_port(.VAR, x3)})
		node_ope2 := create_op(program, type, {make_port(.VAR, x2), make_port(.VAR, x4)})

		link(program, {node_ope1, pair_ope.left})
		link(program, {node_ope2, pair_ope.right})

		delete_node(program, addr_ope)
	}

	delete_node(program, addr_con)
}

@(private = "file")
cond :: proc(program: ^Program, redex: Pair) {
	when PROFILE do prof_count(.Cond)
	swi, num := redex.left, redex.right

	if port_tag(swi) != .SWI do swi, num = num, swi

	addr_swi := port_addr(swi)
	pair := arena.at(&program.nodes, addr_swi)^

	type := num_type(num)
	addr_num := num_addr(num)
	when PROFILE do prof_num(.Read)
	value := arena.at(&program.nums, addr_num)^

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
		node_con := create_node(program, .CON, {pair.right, make_port(.ERA, 0)})

		link(program, {pair.left, node_con})
	} else {
		num_new := make_num_port(type, alloc_num(program, value))

		node_con1 := create_node(program, .CON, {num_new, pair.right})
		node_con2 := create_node(program, .CON, {make_port(.ERA, 0), node_con1})

		link(program, {pair.left, node_con2})
	}

	delete_num(program, addr_num)
}

// TODO: handle case where left is not a num
@(private = "file")
operate :: proc(program: ^Program, redex: Pair) {
	when PROFILE do prof_count(.Operate)
	op, num := redex.left, redex.right

	if port_tag(op) != .OPE do op, num = num, op

	type := op_type(op)
	addr := op_addr(op)

	pair := arena.at(&program.nodes, addr)^

	// swap rule: # ~ $(a, b) -> a ~ $(#, b)
	if port_tag(pair.left) != .NUM {
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
		case .Mul:
			result = mul(value_left, value_right)
		case .Div:
			result = div(value_left, value_right)
		case:
			panic("Unsupported operation")
		}

		delete_num(program, num_addr(left))
		delete_num(program, num_addr(right))

		num_new := make_num_port(result_type, alloc_num(program, result))

		link(program, {num_new, pair.right})
	}
}

@(private = "file")
get_num_values :: proc(program: ^Program, a, b: Port) -> (Num_Value, Num_Value, Num_Type) {
	a, b := a, b

	type_a := num_type(a)
	type_b := num_type(b)

	if type_a < type_b {
		a, b = b, a
		type_a, type_b = type_b, type_a
	}

	when PROFILE do prof_num(.Read)
	value_a := arena.at(&program.nums, num_addr(a))^

	when PROFILE do prof_num(.Read)
	value_b := arena.at(&program.nums, num_addr(b))^

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
add :: proc(a, b: Num_Value) -> u32 {
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
sub :: proc(a, b: Num_Value) -> u32 {
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

@(private = "file")
mul :: proc(a, b: Num_Value) -> u32 {
	switch v in a {
	case f32:
		return transmute(u32)(v * b.(f32))
	case i32:
		return transmute(u32)(v * b.(i32))
	case u32:
		return transmute(u32)(v * b.(u32))
	}
	unreachable()
}

@(private = "file")
div :: proc(a, b: Num_Value) -> u32 {
	switch v in a {
	case f32:
		return transmute(u32)(v / b.(f32))
	case i32:
		return transmute(u32)(v / b.(i32))
	case u32:
		return transmute(u32)(v / b.(u32))
	}
	unreachable()
}

@(private = "file", init)
fmt_program :: proc "contextless" () {
	context = runtime.default_context()
	if fmt._user_formatters == nil do fmt.set_user_formatters(new(map[typeid]fmt.User_Formatter))

	fmt.register_user_formatter(
		type_info_of(Program).id,
		proc(fi: ^fmt.Info, arg: any, verb: rune) -> bool {
			m := cast(^Program)arg.data

			switch verb {
			case 'v':
				fmt.wprintfln(fi.writer, "Program{{")

				fmt.wprintfln(fi.writer, "\tNodes: %d", arena.high_water(&m.nodes))

				fmt.wprintfln(fi.writer, "\tRedexes:")

				for index in 0 ..< queue.len(&m.redexes) {
					redex := queue.get(&m.redexes, index)
					fmt.wprintfln(fi.writer, "\t\t%4d:\t%v\t~\t%v", index, redex.left, redex.right)
				}

				fmt.wprintfln(fi.writer, "\tVars: %d", arena.high_water(&m.vars))

				fmt.wprintfln(fi.writer, "\tNums: %d", arena.high_water(&m.nums))

				fmt.wprintf(fi.writer, "}}")
			case:
				return false
			}

			return true
		},
	)
}
