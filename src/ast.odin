package main

Term :: struct {
	kind: Term_Kind,
	data: union {
		Var_Data,
		Node_Data,
		Num_Data,
	},
	pos:  struct {
		line:   int,
		column: int,
		len:    int,
	},
}

Var_Data :: struct {
	name: string,
}

Node_Data :: struct {
	left:  ^Term,
	right: ^Term,
}

Num_Data :: struct {
	dtype: Data_Type,
	value: union {
		u32,
		i32,
		f32,
	},
}

Data_Type :: enum {
	Uint,
	Int,
	Float,
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
