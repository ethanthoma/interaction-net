package main

import "core:encoding/ansi"
import "core:fmt"
import "core:mem"
import "core:strconv"
import "core:testing"

Parser :: struct {
	tokens:      []Token,
	current:     int,
	definitions: map[string]Definition,
	err_ctx:     Error_Context,
	allocator:   mem.Allocator,
}

make_parser :: proc(tokens: []Token) -> (p: Parser) {
	p.tokens = tokens

	arena := new(mem.Arena)
	mem.arena_init(arena, make([]byte, 1 << 16))
	p.allocator = mem.arena_allocator(arena)

	p.err_ctx = {1, 1, 1}

	return p
}

delete_parser :: proc(p: ^Parser) {
	free_all(p.allocator)
	arena := cast(^mem.Arena)p.allocator.data
	delete(arena.data)
	free(arena)
}

@(private = "file")
delete_term :: proc(term: ^Term) {
	if node_payload, match := term.payload.(Node_Payload); match {
		delete_term(node_payload.left)
		delete_term(node_payload.right)
	}

	free(term)
}

parse :: proc(p: ^Parser) -> (definitions: map[string]Definition, ok: bool = true) {
	context.allocator = p.allocator
	for !is_at_end(p) {
		parse_definition(p) or_return
	}

	return p.definitions, true
}

@(private = "file")
is_at_end :: proc(p: ^Parser) -> bool {
	return p.current == len(p.tokens) - 1
}

@(private = "file")
parse_definition :: proc(p: ^Parser) -> (ok: bool = true) {
	sym := expect(p, .SYMBOL) or_return

	token := expect(p, .IDENTIFIER) or_return

	expect(p, .EQUALS) or_return

	name := token.lexeme
	if name in p.definitions {
		error(
			p,
			{sym.position.line, sym.position.column, sym.position.len + token.position.len},
			"`@%s` is already defined",
			name,
		)
		return false
	}

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
	defer if !ok {
		error(p, token.position, "expected token %v, got %v", type, token.type)
	}

	if token, ok = peek(p); token.type == type {
		p.current += 1
		return token, true
	}

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
		return p.tokens[p.current], false
	}

	return p.tokens[p.current], true
}

@(private = "file")
parse_term :: proc(p: ^Parser) -> (term: ^Term, ok: bool = true) {
	if is_at_end(p) {
		token := p.tokens[p.current - 1]
		error(p, token.position, "unexpected EOF")
		return term, false
	}

	term = new(Term)
	defer if !ok do free(term)

	#partial switch token, _ := advance_token(p); token.type {
	case .SYMBOL:
		term.pos = token.position

		token = expect(p, .IDENTIFIER) or_return

		term.pos.len += len(token.lexeme)

		term.kind = .REF

		term.payload = Var_Payload {
			name = token.lexeme,
		}
	case .IDENTIFIER:
		term.pos = token.position

		switch token.lexeme {
		case "ERA":
			term.kind = .ERA

			expect(p, .LEFT_PAREN) or_return
			expect(p, .RIGHT_PAREN) or_return
		case "DUP", "CON", "SWI":
			switch token.lexeme {
			case "DUP":
				term.kind = .DUP
			case "CON":
				term.kind = .CON
			case "SWI":
				term.kind = .SWI
			}

			expect(p, .LEFT_PAREN) or_return

			left := parse_term(p) or_return
			defer if !ok do delete_term(left)

			expect(p, .COMMA) or_return

			right := parse_term(p) or_return
			defer if !ok do delete_term(right)

			expect(p, .RIGHT_PAREN) or_return

			term.payload = Node_Payload {
				left  = left,
				right = right,
			}
		case:
			term.kind = .VAR
			term.payload = Var_Payload {
				name = token.lexeme,
			}
		}
	case .NUMBER:
		term.pos = token.position

		term.kind = .NUM

		if value, is_uint := strconv.parse_uint(token.lexeme, 10); is_uint {
			term.payload = Num_Payload{.Uint, cast(u32)value}
		} else if value, is_int := strconv.parse_int(token.lexeme, 10); is_int {
			term.payload = Num_Payload{.Int, cast(i32)value}
		} else if value, is_float := strconv.parse_f32(token.lexeme); is_float {
			term.payload = Num_Payload{.Float, value}
		} else {
			error(p, token.position, "number is not parsable: `%s`", token.lexeme)
			return term, false
		}
	case .OPERATION:
		term.pos = token.position

		term.kind = .OPE

		type: Op_Type
		switch token.lexeme {
		case "+":
			type = .Add
		case "-":
			type = .Sub
		case "*":
			type = .Mul
		case "/":
			type = .Div
		}

		expect(p, .LEFT_PAREN) or_return

		left := parse_term(p) or_return
		defer if !ok do delete_term(left)

		expect(p, .COMMA) or_return

		right := parse_term(p) or_return
		defer if !ok do delete_term(right)

		expect(p, .RIGHT_PAREN) or_return

		term.payload = Op_Payload{type, {left, right}}
	case:
		error(
			p,
			token.position,
			"expected token to be %v, %v, or %v, got %v",
			Token_Type.IDENTIFIER,
			Token_Type.SYMBOL,
			Token_Type.NUMBER,
			token.type,
		)
		return term, false
	}

	return term, true
}

@(private = "file")
error :: proc(p: ^Parser, position: Position, msg: string, args: ..any) {
	p.err_ctx = {position.line, position.column, position.len}
	fmt.eprint(ansi.CSI + ansi.FG_RED + ansi.SGR + "Error" + ansi.CSI + ansi.RESET + ansi.SGR)
	fmt.eprintf(" (%d:%d): ", p.err_ctx.line, p.err_ctx.column)
	fmt.eprintf(msg, ..args)
	fmt.eprintf("\n")
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
	defer delete_tokenizer(&tokenizer)

	tokens, token_ok := tokenize(&tokenizer)
	testing.expect(t, token_ok, "Tokenizing should succeed")

	parser := make_parser(tokens)
	defer delete_parser(&parser)

	definitions, parse_ok := parse(&parser)

	testing.expect(t, parse_ok, "Parsing should succeed")

	testing.expect(t, len(definitions) == 1, "Expected only one definition")

	root, ok := definitions["root"]

	testing.expect(t, ok, "Should have root def")

	// TODO: IDK how to actually test this lol
}
