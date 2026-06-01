package main

import "core:testing"

@(private = "file")
CLOSED :: []string {
	"@root = 14.",
	"@root = a & -5 ~ +(3.23, a)",
	"@root = a & 5. ~ /(10, a)",
	"@root = ERA() & ERA() ~ ERA()",
	`@root = CON(a, b)
		& CON(0, c) ~ @succ & CON(c, DUP(a, d)) ~ @succ
		& CON(d, b) ~ @decr
	@decr = CON(a, CON(a, 1))
	@succ = CON(CON(1, a), a)`,
	`@root = CON(a, b)
		& @cond ~ CON(0, a)
		& @cond ~ CON(1, b)
	@cond = CON(a, SWI(CON(5, 3), a))`,
}

@(test)
test_runtime_determinism :: proc(t: ^testing.T) {
	for src in CLOSED {
		book, ok := compile(src)
		if !testing.expectf(t, ok, "compile failed: %q", src) do continue
		defer delete_book(&book)

		a := evaluate(&book)
		defer delete(a)
		b := evaluate(&book)
		defer delete(b)

		testing.expectf(t, a == b, "non-deterministic: %q -> %q vs %q", src, a, b)
	}
}

@(test)
test_runtime_confluence :: proc(t: ^testing.T) {
	for src in CLOSED {
		book, ok := compile(src)
		if !testing.expectf(t, ok, "compile failed: %q", src) do continue
		defer delete_book(&book)

		fifo := evaluate(&book)
		defer delete(fifo)

		for seed in u64(1) ..= 8 {
			shuffled := evaluate(&book, seed)
			defer delete(shuffled)
			testing.expectf(
				t,
				fifo == shuffled,
				"non-confluent %q: fifo=%q seed=%d -> %q",
				src,
				fifo,
				seed,
				shuffled,
			)
		}
	}
}
