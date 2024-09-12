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
	last_index := len(net.nodes) - 1

	if node.index != last_index {
		last_node := net.nodes[last_index]
		net.nodes[node.index] = last_node
		last_node.index = node.index

		update_references(net, last_index, node.index)
	}

	pop(&net.nodes)
	free(node)
}

update_references :: proc(net: ^Net, old_index, new_index: int) {
	for node in net.nodes {
		switch &data in &node.data {
		case Nullary_Node:
			if bound, is_bound := data.ports[0].(Bound); is_bound && bound.index == old_index {
				data.ports[0] = Bound {
					index = new_index,
					slot  = bound.slot,
				}
			}
		case Binary_Node:
			for i in 0 ..= 2 {
				if bound, is_bound := data.ports[i].(Bound); is_bound && bound.index == old_index {
					data.ports[i] = Bound {
						index = new_index,
						slot  = bound.slot,
					}
				}
			}
		}
	}

	// Update redexes
	for &redex in net.redexes {
		if redex.a.index == old_index {
			redex.a.index = new_index
		}
		if redex.b.index == old_index {
			redex.b.index = new_index
		}
	}
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
		interact_gamma_delta(net, node_a, node_b)
	case (type_a == .CON && type_b == .ERA) || (type_a == .ERA && type_b == .CON):
		fmt.println("γε")
		interact_gamma_epsilon(net, node_a, node_b)
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
	gamma_node := node_a.type == .CON ? node_a : node_b
	delta_node := node_a.type == .DUP ? node_a : node_b

	gamma_ports := gamma_node.data.(Binary_Node).ports
	delta_ports := delta_node.data.(Binary_Node).ports

	new_con1 := create_node(net, .CON)
	new_con2 := create_node(net, .CON)

	new_dup1 := create_node(net, .DUP)
	new_dup2 := create_node(net, .DUP)

	connect_ports(net, {new_dup1, 1}, {new_con1, 2})
	connect_ports(net, {new_dup1, 2}, {new_con2, 2})
	connect_ports(net, {new_dup2, 1}, {new_con1, 1})
	connect_ports(net, {new_dup2, 2}, {new_con2, 1})

	if port, ok := gamma_ports[1].(Bound); ok {
		connect_ports(net, {new_dup2, 0}, port)
	}
	if port, ok := gamma_ports[2].(Bound); ok {
		connect_ports(net, {new_dup1, 0}, port)
	}
	if port, ok := delta_ports[1].(Bound); ok {
		connect_ports(net, {new_con1, 0}, port)
	}
	if port, ok := delta_ports[2].(Bound); ok {
		connect_ports(net, {new_con2, 0}, port)
	}

	delete_node(net, gamma_node)
	delete_node(net, delta_node)
}

interact_gamma_epsilon :: proc(net: ^Net, node_a, node_b: ^Node) {
	gamma_node := node_a.type == .CON ? node_a : node_b
	epsilon_node := node_a.type == .ERA ? node_a : node_b

	gamma_ports := gamma_node.data.(Binary_Node).ports
	epsilon_ports := epsilon_node.data.(Nullary_Node).ports

	new_era1 := create_node(net, .ERA)
	new_era2 := create_node(net, .ERA)

	if port, ok := gamma_ports[1].(Bound); ok {
		connect_ports(net, {new_era1, 0}, port)
	}
	if port, ok := gamma_ports[2].(Bound); ok {
		connect_ports(net, {new_era2, 0}, port)
	}

	delete_node(net, gamma_node)
	delete_node(net, epsilon_node)
}

interact_delta_epsilon :: proc(net: ^Net, node_a, node_b: ^Node) {
	delta_node := node_a.type == .DUP ? node_a : node_b
	epsilon_node := node_a.type == .ERA ? node_a : node_b

	delta_ports := delta_node.data.(Binary_Node).ports
	epsilon_ports := epsilon_node.data.(Nullary_Node).ports

	new_era1 := create_node(net, .ERA)
	new_era2 := create_node(net, .ERA)

	if port, ok := delta_ports[1].(Bound); ok {
		connect_ports(net, {new_era1, 0}, port)
	}
	if port, ok := delta_ports[2].(Bound); ok {
		connect_ports(net, {new_era2, 0}, port)
	}

	delete_node(net, delta_node)
	delete_node(net, epsilon_node)
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

	con := create_node(&net, .CON)
	dup := create_node(&net, .DUP)
	era := create_node(&net, .ERA)

	connect_ports(&net, {con, 0}, {era, 0})

	for node in net.nodes {
		fmt.println(node^)
	}

	evaluate(&net)

	for node in net.nodes {
		fmt.println(node^)
	}
}
