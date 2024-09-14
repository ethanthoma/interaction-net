package main

import "core:fmt"
import "core:testing"

Term_Kind :: enum {
	VAR,
	ERA,
	REF,
	CON,
	DUP,
}

Term :: struct {
	kind: Term_Kind,
	data: union {
		Var_Data,
		Node_Data,
	},
}

Var_Data :: struct {
	name: string,
}

Node_Data :: struct {
	left:  ^Term,
	right: ^Term,
}

Redex :: struct {
	left:  ^Term,
	right: ^Term,
}

Definition :: struct {
	name:    string,
	root:    ^Term,
	redexes: [dynamic]Redex,
}

Parser :: struct {
	tokens:      []Token,
	current:     int,
	definitions: map[string]Definition,
}

make_parser :: proc(tokens: []Token) -> Parser {
	return Parser{tokens = tokens, current = 0, definitions = make(map[string]Definition)}
}

delete_parser :: proc(p: ^Parser) {
	delete(p.definitions)
}

// parse abuses or_return but doesn't track errors well (ie, fails cause no tilde, no info why/where)
// https://github.com/odin-lang/Odin/blob/v0.13.0/core/encoding/json/parser.odin
// odin json parser creates its own tokenizer where this one expects a list of tokens...
// not sure which is better
parse :: proc(p: ^Parser) -> (ok: bool) {
	for !is_at_end(p) {
		parse_definition(p) or_return
	}
	return true
}

@(private = "file")
is_at_end :: proc(p: ^Parser) -> bool {
	return p.current == len(p.tokens) - 1
}

@(private = "file")
parse_definition :: proc(p: ^Parser) -> (ok: bool) {
	expect(p, .SYMBOL) or_return

	token := expect(p, .IDENTIFIER) or_return

	expect(p, .EQUALS) or_return

	name := token.lexeme
	root := parse_term(p) or_return

	def := Definition {
		name    = name,
		root    = root,
		redexes = make([dynamic]Redex),
	}

	for _, match := expect(p, .AMPERSAND); match; _, match = expect(p, .AMPERSAND) {
		left := parse_term(p) or_return

		expect(p, .TILDE) or_return

		right := parse_term(p) or_return

		append(&def.redexes, Redex{left = left, right = right})
	}

	p.definitions[name] = def
	return true
}

@(private = "file")
expect :: proc(p: ^Parser, type: Token_Type) -> (token: Token, ok: bool) {
	if is_at_end(p) {
		return token, false
	}

	if token = p.tokens[p.current]; token.type == type {
		p.current += 1
		return token, true
	}

	return token, false
}

@(private = "file")
parse_term :: proc(p: ^Parser) -> (term: ^Term, ok: bool) {
	if is_at_end(p) {
		return term, false
	}

	term = new(Term)
	defer {if !ok do free(term)}

	if token, match := expect(p, .SYMBOL); match {
		term.kind = .REF
		left := parse_term(p) or_return
		term.data = Node_Data {
			left  = left,
			right = nil,
		}
	} else if token, match := expect(p, .IDENTIFIER); match {
		switch token.lexeme {
		case "ERA":
			term.kind = .ERA
			expect(p, .LEFT_PAREN) or_return
			expect(p, .RIGHT_PAREN) or_return
		// TODO: both DUP and CON are binary so they do the same checks, should
		// look into grouping them. Maybe some enum switch?
		case "DUP":
			term.kind = .DUP

			expect(p, .LEFT_PAREN) or_return
			left := parse_term(p) or_return
			expect(p, .COMMA) or_return
			right := parse_term(p) or_return
			expect(p, .RIGHT_PAREN) or_return

			term.data = Node_Data {
				left  = left,
				right = right,
			}
		case "CON":
			term.kind = .CON

			expect(p, .LEFT_PAREN) or_return
			left := parse_term(p) or_return
			expect(p, .COMMA) or_return
			right := parse_term(p) or_return
			expect(p, .RIGHT_PAREN) or_return

			term.data = Node_Data {
				left  = left,
				right = right,
			}
		case:
			term.kind = .VAR
			term.data = Var_Data {
				name = token.lexeme,
			}
		}
	} else {
		token, _ := advance_token(p)
		// TODO: odin tokenizer has an intersting way of tracking errors, should 
		// look into that
		fmt.printfln("Error: expected symbol or identifer, found %v", token.type)
		return term, false
	}

	return term, true
}

// TODO: can be removed, its used for one error and that's it
@(private = "file")
advance_token :: proc(p: ^Parser) -> (token: Token, ok: bool) {
	if is_at_end(p) {
		return token, false
	}

	token = p.tokens[p.current]
	p.current += 1

	return token, true
}

// ** Testing **
@(test)
test_parser :: proc(t: ^testing.T) {
	input := `
        @root = a 
            & CON(ERA(), DUP(c, CON(b, DUP(c, b)))) 
            ~ CON(a, DUP(c, CON(b, DUP(c, b))))
    `

	tokenizer := make_tokenizer(input)

	tokenize(&tokenizer)
	defer delete_tokenizer(&tokenizer)

	tokens := tokenizer.tokens[:]

	parser := make_parser(tokens)

	testing.expect(t, parse(&parser), "Parsing should succeed")

	definitions := parser.definitions

	testing.expect(t, len(definitions) == 1, "Expected only one definition")

	root, ok := definitions["root"]

	testing.expect(t, ok, "Should have root def")

	// TODO: IDK how to actually test this lol
}
