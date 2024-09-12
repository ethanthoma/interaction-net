package main

import "core:fmt"

Node_Type :: enum {
	ERA,
	CON,
	DUP,
}

Node :: struct {
	index: int,
	type:  Node_Type,
	data:  union {
		Nullary_Node,
		Binary_Node,
	},
}

Nullary_Node :: struct {
	ports: [1]Port,
}

Binary_Node :: struct {
	ports: [3]Port,
}

Port :: union {
	Bound,
	Free,
}

Bound :: struct {
	index: int,
	slot:  int,
}

Pair :: struct {
	a: Bound,
	b: Bound,
}

Free :: struct {}

Net :: struct {
	nodes:   [dynamic]^Node,
	redexes: [dynamic]Pair,
}

create_node :: proc(net: ^Net, type: Node_Type) -> int {
	index := len(net.nodes)
	node := new(Node)
	node.index = index
	node.type = type

	switch type {
	case .ERA:
		node.data = Nullary_Node {
			ports = [1]Port{Free{}},
		}
	case .CON, .DUP:
		node.data = Binary_Node {
			ports = [3]Port{Free{}, Free{}, Free{}},
		}
	}

	append(&net.nodes, node)
	return index
}

delete_node :: proc(net: ^Net, node: ^Node) {
	last_node := pop(&net.nodes)

	if node.index != len(net.nodes) {
		last_node.index = node.index
		net.nodes[node.index]^ = last_node^
	}

	free(node)
}

connect_ports :: proc(net: ^Net, port_a: Bound, port_b: Bound) {
	node_a := net.nodes[port_a.index]
	node_b := net.nodes[port_b.index]

	switch &data in &node_a.data {
	case Nullary_Node:
		data.ports[port_a.slot] = port_b
	case Binary_Node:
		data.ports[port_a.slot] = port_b
	}

	switch &data in &node_b.data {
	case Nullary_Node:
		data.ports[port_b.slot] = port_a
	case Binary_Node:
		data.ports[port_b.slot] = port_a
	}

	if port_a.slot == 0 && port_b.slot == 0 {
		add_redux(net, {port_a, port_b})
	}
}

add_redux :: proc(net: ^Net, pair: Pair) {
	append(&net.redexes, pair)
}

evaluate :: proc(net: ^Net) {
	for len(net.redexes) > 0 {
		redex := pop(&net.redexes)
		interact(net, redex)
	}
}

interact :: proc(net: ^Net, redex: Pair) {
	node_a := net.nodes[redex.a.index]
	node_b := net.nodes[redex.b.index]

	type_a := node_a.type
	type_b := node_b.type

	switch {
	case (type_a == .CON && type_b == .DUP) || (type_a == .DUP && type_b == .CON):
		fmt.println("γδ")
	case (type_a == .CON && type_b == .ERA) || (type_a == .ERA && type_b == .CON):
		fmt.println("γε")
	case (type_a == .DUP && type_b == .ERA) || (type_a == .ERA && type_b == .DUP):
		fmt.println("δε")
	case type_a == .CON && type_b == .CON:
		fmt.println("γγ")
		interact_gamma_gamma(net, node_a, node_b)
	case type_a == .DUP && type_b == .DUP:
		fmt.println("δδ")
		interact_delta_delta(net, node_a, node_b)
	case type_a == .ERA && type_b == .ERA:
		fmt.println("εε")
		interact_epsilon_epsilon(net, node_a, node_b)
	}
}

interact_gamma_delta :: proc(net: ^Net, node_a, node_b: ^Node) {
	ports_a := node_a.data.(Binary_Node).ports
	ports_b := node_b.data.(Binary_Node).ports
}

interact_gamma_gamma :: proc(net: ^Net, node_a, node_b: ^Node) {
	ports_a := node_a.data.(Binary_Node).ports
	ports_b := node_b.data.(Binary_Node).ports

	if port_a, ok := ports_a[1].(Bound); ok {
		if port_b, ok := ports_b[2].(Bound); ok {
			connect_ports(net, port_a, port_b)
		}
	}

	if port_a, ok := ports_a[2].(Bound); ok {
		if port_b, ok := ports_b[1].(Bound); ok {
			connect_ports(net, port_a, port_b)
		}
	}

	delete_node(net, node_a)
	delete_node(net, node_b)
}

interact_delta_delta :: proc(net: ^Net, node_a, node_b: ^Node) {
	ports_a := node_a.data.(Binary_Node).ports
	ports_b := node_b.data.(Binary_Node).ports

	if port_a, ok := ports_a[1].(Bound); ok {
		if port_b, ok := ports_b[1].(Bound); ok {
			connect_ports(net, port_a, port_b)
		}
	}

	if port_a, ok := ports_a[2].(Bound); ok {
		if port_b, ok := ports_b[2].(Bound); ok {
			connect_ports(net, port_a, port_b)
		}
	}

	delete_node(net, node_a)
	delete_node(net, node_b)
}

interact_epsilon_epsilon :: proc(net: ^Net, node_a, node_b: ^Node) {
	delete_node(net, node_a)
	delete_node(net, node_b)
}

main :: proc() {
	net: Net
	defer delete(net.nodes)
	defer delete(net.redexes)

	dup1 := create_node(&net, .DUP)
	dup2 := create_node(&net, .DUP)

	connect_ports(&net, {dup1, 0}, {dup2, 0})

	era1 := create_node(&net, .ERA)
	era2 := create_node(&net, .ERA)

	connect_ports(&net, {era1, 0}, {era2, 0})

	fmt.println(net)

	evaluate(&net)

	fmt.println(net)
}
