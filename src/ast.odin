package main

Term :: struct {
	kind:    Tag,
	payload: union {
		Var_Payload,
		Node_Payload,
		Num_Payload,
		Op_Payload,
	},
	pos:     Position,
}

Var_Payload :: struct {
	name: string,
}

Node_Payload :: struct {
	left:  ^Term,
	right: ^Term,
}

Num_Payload :: struct {
	type:  Num_Type,
	value: Num_Value,
}

Op_Payload :: struct {
	type: Op_Type,
	node: Node_Payload,
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
