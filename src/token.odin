package main

Token_Type :: enum {
	IDENTIFIER,
	SYMBOL,
	LEFT_PAREN,
	RIGHT_PAREN,
	COMMA,
	EQUALS,
	AMPERSAND,
	TILDE,
	EOF,
}

Token :: struct {
	type:   Token_Type,
	lexeme: string,
	line:   int,
	column: int,
}
