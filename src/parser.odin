package main

import "core:fmt"
import "core:strconv"
import "core:strings"
import "core:unicode"

Token_Type :: enum {
	VAR,
	NODE,
	EQUALS,
	LEFT_PAREN,
	RIGHT_PAREN,
	COMMA,
	EOF,
}

Token :: struct {
	type:  Token_Type,
	value: string,
}

Parser :: struct {
	tokens:   []Token,
	current:  int,
	net:      ^Net,
	node_map: map[string]int,
}

parse_net :: proc(input: string) -> (net: Net, ok: bool) {
	parser := Parser {
		net = &net,
	}
	parser.node_map = make(map[string]int)
	defer delete(parser.node_map)

	tokens := tokenize(input)
	defer delete(tokens)
	parser.tokens = tokens

	for token in tokens {
		fmt.println(token)
	}

	return net, true
}

tokenize :: proc(input: string) -> []Token {
	tokens: [dynamic]Token
	for i := 0; i < len(input); {
		switch {
		case input[i] == '#':
			start := i
			i += 1
			for i < len(input) &&
			    (unicode.is_letter(rune(input[i])) ||
					    unicode.is_digit(rune(input[i])) ||
					    input[i] == '_') {
				i += 1
			}
			append(&tokens, Token{.VAR, input[start:i]})
		case unicode.is_letter(rune(input[i])):
			start := i
			for i < len(input) &&
			    (unicode.is_letter(rune(input[i])) ||
					    unicode.is_digit(rune(input[i])) ||
					    input[i] == '_') {
				i += 1
			}
			append(&tokens, Token{.NODE, input[start:i]})
		case input[i] == '=':
			append(&tokens, Token{.EQUALS, "="})
			i += 1
		case input[i] == '(':
			append(&tokens, Token{.LEFT_PAREN, "("})
			i += 1
		case input[i] == ')':
			append(&tokens, Token{.RIGHT_PAREN, ")"})
			i += 1
		case input[i] == ',':
			append(&tokens, Token{.COMMA, ","})
			i += 1
		case unicode.is_space(rune(input[i])):
			i += 1
		case:
			fmt.printf("Unexpected character: %c\n", input[i])
			i += 1
		}
	}

	append(&tokens, Token{.EOF, ""})
	return tokens[:]
}

import "core:testing"

@(test)
test_parser :: proc(t: ^testing.T) {
	input := `
    #root = CON(
        DUP(#left, #right),
        ERA(),
    )

    #left = DUP(root, CON(ERA(), ERA()))
    #right = DUP(root, CON(ERA(), ERA()))
    `

	net, ok := parse_net(input)
	defer delete(net.nodes)
	defer delete(net.redexes)

	testing.expect(t, ok, "Parsing should succeed")
}
