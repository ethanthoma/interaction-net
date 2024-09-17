package main

Port :: struct {
	tag:  Term_Kind,
	data: union {
		Node_Address, // CON DUP
		Var_Address, // VAR
		Empty, // ERA
	},
}

Node_Address :: distinct u32
Var_Address :: distinct u32
Empty :: struct {}

Pair :: struct {
	left, right: Port,
}
