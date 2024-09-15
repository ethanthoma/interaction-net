package main

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
