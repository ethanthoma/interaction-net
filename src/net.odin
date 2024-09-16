package main

Port :: struct {
	tag:  Term_Kind,
	data: union {
		Node_Address, // CON DUP
		Ref_Address, // REF
		Var_Name, // VAR
		Empty, // ERA
	},
}

Node_Address :: distinct u32
Ref_Address :: distinct u32
Var_Name :: distinct string
Empty :: struct {}

Pair :: struct {
	left, right: Port,
}
