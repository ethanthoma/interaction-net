package main

import "core:fmt"
import "core:strings"
import "core:testing"

Tokenizer :: struct {
	input:                         string,
	offset, current, line, column: int,
	tokens:                        [dynamic]Token,
}

make_tokenizer :: proc(input: string) -> Tokenizer {
	return Tokenizer {
		input = input,
		offset = 0,
		current = 0,
		line = 1,
		column = 1,
		tokens = make([dynamic]Token),
	}
}

delete_tokenizer :: proc(t: ^Tokenizer) {
	delete(t.tokens)
}

tokenize :: proc(t: ^Tokenizer) -> (tokens: []Token, ok: bool = true) {
	for !is_at_end(t) {
		t.offset = t.current
		scan(t) or_return
	}

	add_token(t, .EOF)

	return t.tokens[:], true
}

@(private = "file")
is_at_end :: proc(t: ^Tokenizer) -> bool {
	return t.current >= len(t.input)
}

@(private = "file")
scan :: proc(t: ^Tokenizer) -> (ok: bool = true) {
	skip_whitespace(t)

	c, not_eof := advance_rune(t)
	if !not_eof {
		return true
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
	case '0' ..= '9':
		scan_number(t)
	case 'A' ..= 'Z', 'a' ..= 'z':
		scan_identifier(t)
	case:
		error(t, "illegal character '%r'", c)
		return false
	}

	return true
}

@(private = "file")
skip_whitespace :: proc(t: ^Tokenizer) {
	for {
		c, ok := peek(t)
		if !ok do return

		switch c {
		case '\n':
			t.line += 1
			t.column = 1
			t.current += 1
			t.offset += 1
		case ' ', '\t', '\r', '\v', '\f':
			t.current += 1
			t.column += 1
			t.offset += 1
		case:
			return
		}
	}
}

@(private = "file")
peek :: proc(t: ^Tokenizer) -> (c: rune, ok: bool) {
	if is_at_end(t) {
		return c, false
	}

	return rune(t.input[t.current]), true
}

@(private = "file")
advance_rune :: proc(t: ^Tokenizer) -> (c: rune, ok: bool) {
	c = peek(t) or_return
	t.current += 1
	return c, true
}

@(private = "file")
add_token :: proc(t: ^Tokenizer, type: Token_Type) {
	text := t.input[t.offset:t.current]
	token := Token {
		type   = type,
		lexeme = text,
		line   = t.line,
		column = t.column,
	}
	t.column += len(text)
	t.offset = t.current
	append(&t.tokens, token)
}

@(private = "file")
scan_number :: proc(t: ^Tokenizer) {
	has_dot := false
	for c, ok := peek(t); ok && (is_numeric(c) || c == '.'); c, ok = peek(t) {
		if has_dot && c == '.' {
			error(t, "only one period allowed in a number")
		}
		advance_rune(t)
	}
	add_token(t, .NUMBER)
}

@(private = "file")
is_numeric :: proc(c: rune) -> bool {
	return c >= '0' && c <= '9'
}

@(private = "file")
scan_identifier :: proc(t: ^Tokenizer) {
	for c, ok := peek(t); ok && is_alphanumeric(c); c, ok = peek(t) {
		advance_rune(t)
	}
	add_token(t, .IDENTIFIER)
}

@(private = "file")
is_alphanumeric :: proc(c: rune) -> bool {
	return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c == '_' || is_numeric(c)
}

@(private = "file")
error :: proc(t: ^Tokenizer, msg: string, args: ..any) {
	fmt.eprintf("Tokenizer: (%d:%d): ", t.line, t.column)
	fmt.eprintf(msg, ..args)
	fmt.eprintf("\n")
}

// ** Testing **
@(test)
test_tokenize_simple :: proc(t: ^testing.T) {
	input := "@root = ERA()"

	tokenizer := make_tokenizer(input)

	tokenize(&tokenizer)
	defer delete_tokenizer(&tokenizer)

	tokens := tokenizer.tokens

	expected := [?]Token_Type {
		.SYMBOL,
		.IDENTIFIER,
		.EQUALS,
		.IDENTIFIER,
		.LEFT_PAREN,
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

@(test)
test_tokenize_complex :: proc(t: ^testing.T) {
	input := `
        @root = a 
            & @second ~ CON(a, @first)

        @first = DUP(a, CON(b, DUP(a, b)))

        @second = CON(ERA(), @first)
    `

	tokenizer := make_tokenizer(input)
	defer delete_tokenizer(&tokenizer)

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
