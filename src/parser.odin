package main

import "core:fmt"
import "core:os"
import "core:testing"

Parser :: struct {
	tokens:      []Token,
	current:     int,
	definitions: map[string]Definition,
}

make_parser :: proc(tokens: []Token) -> Parser {
	return Parser{tokens = tokens, current = 0, definitions = make(map[string]Definition)}
}

delete_parser :: proc(p: ^Parser) {
	for _, &def in p.definitions {
		delete_term(def.root)

		for &redex in def.redexes {
			delete_term(redex.left)
			delete_term(redex.right)
		}

		delete(def.redexes)
	}

	delete(p.definitions)
}

delete_term :: proc(term: ^Term) {
	if node_data, match := term.data.(Node_Data); match {
		delete_term(node_data.left)
		delete_term(node_data.right)
	}

	free(term)
}

// parse abuses or_return but doesn't track errors well (ie, fails cause no tilde, no info why/where)
// https://github.com/odin-lang/Odin/blob/v0.13.0/core/encoding/json/parser.odin
// odin json parser creates its own tokenizer where this one expects a list of tokens...
// not sure which is better
parse :: proc(p: ^Parser) -> (ok: bool = true) {
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
parse_definition :: proc(p: ^Parser) -> (ok: bool = true) {
	expect(p, .SYMBOL) or_return

	token := expect(p, .IDENTIFIER) or_return

	expect(p, .EQUALS) or_return

	name := token.lexeme
	if name in p.definitions do return false

	root := parse_term(p) or_return
	defer if !ok do delete_term(root)

	def := Definition {
		name    = name,
		root    = root,
		redexes = make([dynamic]Redex),
	}
	defer if !ok do delete(def.redexes)

	for token, _ = peek(p); token.type == .AMPERSAND; token, _ = peek(p) {
		p.current += 1

		left := parse_term(p) or_return
		defer if !ok do delete_term(left)

		expect(p, .TILDE) or_return

		right := parse_term(p) or_return
		defer if !ok do delete_term(right)

		append(&def.redexes, Redex{left = left, right = right})
	}

	p.definitions[name] = def
	return true
}

@(private = "file")
expect :: proc(p: ^Parser, type: Token_Type) -> (token: Token, ok: bool = true) {
	if token = peek(p) or_return; token.type == type {
		p.current += 1
		return token, true
	}

	error(p, {token.line, token.column}, "expected token %v, got %v", type, token.type)
	return token, false
}

@(private = "file")
advance_token :: proc(p: ^Parser) -> (token: Token, ok: bool = true) {
	token = peek(p) or_return
	p.current += 1

	return token, true
}

@(private = "file")
peek :: proc(p: ^Parser) -> (token: Token, ok: bool = true) {
	if is_at_end(p) {
		return token, false
	}

	return p.tokens[p.current], true
}

@(private = "file")
parse_term :: proc(p: ^Parser) -> (term: ^Term, ok: bool = true) {
	if is_at_end(p) {
		return term, false
	}

	term = new(Term)
	defer if !ok do free(term)

	#partial switch token, _ := advance_token(p); token.type {
	case .SYMBOL:
		token = expect(p, .IDENTIFIER) or_return

		term.kind = .REF

		term.data = Var_Data {
			name = token.lexeme,
		}
	case .IDENTIFIER:
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
			defer if !ok do delete_term(left)

			expect(p, .COMMA) or_return

			right := parse_term(p) or_return
			defer if !ok do delete_term(right)

			expect(p, .RIGHT_PAREN) or_return

			term.data = Node_Data {
				left  = left,
				right = right,
			}
		case "CON":
			term.kind = .CON

			expect(p, .LEFT_PAREN) or_return

			left := parse_term(p) or_return
			defer if !ok do delete_term(left)

			expect(p, .COMMA) or_return

			right := parse_term(p) or_return
			defer if !ok do delete_term(right)

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

	case:
		error(
			p,
			{token.line, token.column},
			"expected token to %v or %v, got %v",
			Token_Type.IDENTIFIER,
			Token_Type.SYMBOL,
			token.type,
		)
	}

	return term, true
}

@(private = "file")
error :: proc(p: ^Parser, pos: struct {
		line, column: int,
	}, msg: string, args: ..any) {
	fmt.eprintf("Parser: (%d:%d): ", pos.line, pos.column)
	fmt.eprintf(msg, ..args)
	fmt.eprintf("\n")

	os.exit(1)
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
	defer delete_parser(&parser)

	testing.expect(t, parse(&parser), "Parsing should succeed")

	definitions := parser.definitions

	testing.expect(t, len(definitions) == 1, "Expected only one definition")

	root, ok := definitions["root"]

	testing.expect(t, ok, "Should have root def")

	// TODO: IDK how to actually test this lol
}
