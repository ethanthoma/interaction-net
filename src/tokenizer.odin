package main

import "core:fmt"
import "core:strings"
import "core:testing"

Tokenizer :: struct {
	input:                 string,
	offset, current, line: int,
	tokens:                [dynamic]Token,
}

init_tokenizer :: proc(input: string) -> Tokenizer {
	return Tokenizer {
		input = input,
		offset = 0,
		current = 0,
		line = 1,
		tokens = make([dynamic]Token),
	}
}

tokenize :: proc(t: ^Tokenizer) -> [dynamic]Token {
	for !is_at_end(t) {
		t.offset = t.current
		scan(t)
	}

	return t.tokens
}

@(test)
test_tokenize_simple :: proc(t: ^testing.T) {
	input := "@root = ERA()"

	tokenizer := init_tokenizer(input)

	tokenize(&tokenizer)

	tokens := tokenizer.tokens

	expected := [?]Token_Type {
		.SYMBOL,
		.IDENTIFIER,
		.EQUALS,
		.IDENTIFIER,
		.LEFT_PAREN,
		.RIGHT_PAREN,
	}

	testing.expectf(
		t,
		len(tokens) == len(expected),
		"Expected length of token is %d, got %d",
		len(expected),
		len(tokens),
	)

	for i in 0 ..< len(expected) {
		testing.expectf(
			t,
			tokens[i].type == expected[i],
			"Expected type %v, got %v at position %d",
			expected[i],
			tokens[i].type,
			i,
		)
	}
}

@(test)
test_tokenize_complex :: proc(t: ^testing.T) {
	input := `
        @root = a 
            & @second ~ CON(a, @first)

        @first = DUP(a, CON(b, DUP(a, b))

        @second = CON(ERA(), @first)
    `

	tokenizer := init_tokenizer(input)

	tokenize(&tokenizer)

	tokens := tokenizer.tokens

	expected := [?]Token_Type {
		.SYMBOL,
		.IDENTIFIER,
		.EQUALS,
		.IDENTIFIER,
		.AMPERSAND,
		.SYMBOL,
		.IDENTIFIER,
		.TILDE,
		.IDENTIFIER,
		.LEFT_PAREN,
		.IDENTIFIER,
		.COMMA,
		.SYMBOL,
		.IDENTIFIER,
		.RIGHT_PAREN,
		.SYMBOL,
		.IDENTIFIER,
		.EQUALS,
		.IDENTIFIER,
		.LEFT_PAREN,
		.IDENTIFIER,
		.COMMA,
		.IDENTIFIER,
		.LEFT_PAREN,
		.IDENTIFIER,
		.COMMA,
		.IDENTIFIER,
		.LEFT_PAREN,
		.IDENTIFIER,
		.COMMA,
		.IDENTIFIER,
		.RIGHT_PAREN,
		.RIGHT_PAREN,
		.SYMBOL,
		.IDENTIFIER,
		.EQUALS,
		.IDENTIFIER,
		.LEFT_PAREN,
		.IDENTIFIER,
		.LEFT_PAREN,
		.RIGHT_PAREN,
		.COMMA,
		.SYMBOL,
		.IDENTIFIER,
		.RIGHT_PAREN,
		.EOF,
	}

	testing.expectf(
		t,
		len(tokens) == len(expected),
		"Expected length of token is %d, got %d",
		len(expected),
		len(tokens),
	)

	for i in 0 ..< len(expected) {
		testing.expectf(
			t,
			tokens[i].type == expected[i],
			"Expected type %v, got %v at position %d",
			expected[i],
			tokens[i].type,
			i,
		)
	}
}

@(private)
is_at_end :: proc(t: ^Tokenizer) -> bool {
	return t.current >= len(t.input)
}

@(private)
scan :: proc(t: ^Tokenizer) {
	skip_whitespace(t)

	c, ok := advance_rune(t)
	if !ok {
		add_token(t, .EOF)
		return
	}

	switch c {
	case '(':
		add_token(t, .LEFT_PAREN)
	case ')':
		add_token(t, .RIGHT_PAREN)
	case ',':
		add_token(t, .COMMA)
	case '=':
		add_token(t, .EQUALS)
	case '&':
		add_token(t, .AMPERSAND)
	case '~':
		add_token(t, .TILDE)
	case '@':
		add_token(t, .SYMBOL)
	case 'A' ..= 'Z', 'a' ..= 'z':
		scan_identifier(t)
	case:
		fmt.printf("Unexpected character: %c at line %d\n", c, t.line)
	}
}

@(test)
test_scan_empty :: proc(t: ^testing.T) {
	input := ""

	tokenizer := init_tokenizer(input)

	scan(&tokenizer)

	tokens := tokenizer.tokens

	testing.expectf(t, len(tokens) == 1, "Expected only 1 token, found %d", len(tokens))
	testing.expectf(t, tokens[0].type == .EOF, "Expected EOF token, found %v", tokens[0].type)
}

@(private)
skip_whitespace :: proc(t: ^Tokenizer) {
	for {
		c, ok := peek(t)
		if !ok do return

		switch c {
		case '\n':
			t.line += 1
			t.current += 1
			t.offset += 1
		case ' ', '\t', '\r', '\v', '\f':
			t.current += 1
			t.offset += 1
		case:
			return
		}
	}
}

@(test)
test_skip_whitespace :: proc(t: ^testing.T) {
	input := "  t  k"

	tokenizer := init_tokenizer(input)

	skip_whitespace(&tokenizer)

	testing.expectf(
		t,
		tokenizer.current == strings.index(input, "t"),
		"Expected %d, actual is %d",
		strings.index(input, "t"),
		tokenizer.current,
	)

	tokenizer.current += 1 // skip over t
	skip_whitespace(&tokenizer)

	testing.expectf(
		t,
		tokenizer.current == strings.index(input, "k"),
		"Expected %d, actual is %d",
		strings.index(input, "k"),
		tokenizer.current,
	)
}

@(private)
peek :: proc(t: ^Tokenizer) -> (c: rune, ok: bool) {
	if is_at_end(t) {
		return {}, false
	}

	return rune(t.input[t.current]), true
}

@(private)
advance_rune :: proc(t: ^Tokenizer) -> (c: rune, ok: bool) {
	c = peek(t) or_return
	t.current += 1
	return c, true
}

@(private)
add_token :: proc(t: ^Tokenizer, type: Token_Type) {
	text := t.input[t.offset:t.current]
	token := Token {
		type   = type,
		lexeme = text,
		line   = t.line,
	}
	t.offset = t.current
	append(&t.tokens, token)
}

@(private)
scan_identifier :: proc(t: ^Tokenizer) {
	for c, ok := peek(t); ok && is_alphanumeric(c); c, ok = peek(t) {
		advance_rune(t)
	}
	add_token(t, .IDENTIFIER)
}

@(private)
is_alphanumeric :: proc(c: rune) -> bool {
	return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c == '_' || (c >= '0' && c <= '9')
}
