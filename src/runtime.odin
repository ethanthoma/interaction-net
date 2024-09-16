package main

import "core:container/queue"
import "core:fmt"

run :: proc(program: ^Program) {
	for redex, ok := queue.pop_front_safe(&program.redexes);
	    ok;
	    redex, ok = queue.pop_front_safe(&program.redexes) {
		interact(program, redex)
	}
}

interact :: proc(program: ^Program, redex: Pair) {
	a, b := redex.left, redex.right

	switch struct {
		a: Term_Kind,
		b: Term_Kind,
	}({a.tag, b.tag}) {
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
		if a.tag == b.tag && a.tag == .VAR {
			link(program, redex)
		} else {
			fmt.eprintfln("Missing rule for %v:%v", a.tag, b.tag)
		}
	}
}

@(private = "file")
commute :: proc(program: ^Program, redex: Pair) {
	fmt.println("γδ")
}

@(private = "file")
annihilate :: proc(program: ^Program, redex: Pair) {
	fmt.println("γγ | δδ")
}

@(private = "file")
void :: proc(program: ^Program, redex: Pair) {
	fmt.println("εε | REF:REF | REF:ε")
}

@(private = "file")
erase :: proc(program: ^Program, redex: Pair) {
	fmt.println("γε | δε | REF:δ")
}

@(private = "file")
link :: proc(program: ^Program, redex: Pair) {
	fmt.println("VAR:_")
}

@(private = "file")
call :: proc(program: ^Program, redex: Pair) {
	fmt.println("REF:γ")
}
