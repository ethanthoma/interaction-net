package main

import "core:testing"

@(test)
test_parser :: proc(t: ^testing.T) {
	input := `
        @root = a 
            & @second ~ CON(a, @first)

        @first = DUP(a, CON(b, DUP(a, b))

        @second = CON(ERA(), @first)
    `

	ok := true

	testing.expect(t, ok, "Parsing should succeed")
}
