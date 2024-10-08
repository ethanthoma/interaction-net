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
	NUMBER,
	OPERATION,
	EOF,
}

Token :: struct {
	type:     Token_Type,
	lexeme:   string,
	position: Position,
}

Position :: struct {
	line:   int,
	column: int,
	len:    int,
}
