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

		serial := evaluate(&book, 1)
		defer delete(serial)

		WORKER_COUNTS :: [?]int{2, 4, 8}
		for workers in WORKER_COUNTS {
			for trial in 0 ..< 16 {
				parallel := evaluate(&book, workers)
				defer delete(parallel)
				testing.expectf(
					t,
					serial == parallel,
					"non-confluent %q: serial=%q workers=%d -> %q",
					src,
					serial,
					workers,
					parallel,
				)
			}
		}
	}
}
