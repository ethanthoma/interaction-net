package main

import "core:fmt"
import "core:strings"
import "shared:arena"

@(deferred_out = delete_serialized_string)
serialize :: proc(program: ^Program, book: ^Book) -> string {
	sb := strings.builder_make()

	serialize_port(program, book, make_port(.VAR, ROOT), &sb)

	return strings.to_string(sb)
}

@(private = "file")
delete_serialized_string :: proc(str: string) {
	delete(str)
}

@(private = "file")
serialize_port :: proc(program: ^Program, book: ^Book, port: Port, sb: ^strings.Builder) {
	#partial switch port_tag(port) {
	case .ERA:
		fmt.sbprint(sb, "ERA()")
	case .REF:
		name := book.names[port_addr(port)]
		fmt.sbprintf(sb, "@%v", name)
	case .VAR:
		got := enter(program, port)
		if got != port {
			serialize_port(program, book, got, sb)
		} else {
			fmt.sbprintf(sb, "v%d", port_addr(port))
		}
	case .NUM:
		type := num_type(port)
		value := arena.at(&program.nums, num_addr(port))^
		switch type {
		case .Uint:
			fmt.sbprintf(sb, "%v", value)
		case .Int:
			fmt.sbprintf(sb, "%v", transmute(i32)value)
		case .Float:
			fmt.sbprintf(sb, "%v", transmute(f32)value)
		}
	case .OPE:
		type := op_type(port)
		addr := op_addr(port)

		#partial switch type {
		case .Add:
			fmt.sbprint(sb, "+(")
		case .Sub:
			fmt.sbprint(sb, "-(")
		case .Mul:
			fmt.sbprint(sb, "*(")
		case .Div:
			fmt.sbprint(sb, "/(")
		case:
			panic("NOT SUPPORTED OP")
		}

		pair := arena.at(&program.nodes, addr)^
		serialize_port(program, book, pair.left, sb)
		fmt.sbprint(sb, ", ")
		serialize_port(program, book, pair.right, sb)
		fmt.sbprint(sb, ")")
	case:
		#partial switch port_tag(port) {
		case .CON:
			fmt.sbprint(sb, "CON(")
		case .DUP:
			fmt.sbprint(sb, "DUP(")
		case .SWI:
			fmt.sbprint(sb, "SWI(")
		}
		pair := arena.at(&program.nodes, port_addr(port))^
		serialize_port(program, book, pair.left, sb)
		fmt.sbprint(sb, ", ")
		serialize_port(program, book, pair.right, sb)
		fmt.sbprint(sb, ")")
	}
}
