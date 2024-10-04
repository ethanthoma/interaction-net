package main

import "core:fmt"
import "core:strings"

@(deferred_out = delete_serialized_string)
serialize :: proc(program: ^Program, book: ^Book) -> string {
	sb := strings.builder_make()

	root_port: Port = {
		tag  = .VAR,
		data = ROOT,
	}

	serialize_port(program, book, root_port, &sb)

	return strings.to_string(sb)
}

@(private = "file")
delete_serialized_string :: proc(str: string) {
	delete(str)
}

@(private = "file")
serialize_port :: proc(program: ^Program, book: ^Book, port: Port, sb: ^strings.Builder) {
	#partial switch port.tag {
	case .ERA:
		fmt.sbprint(sb, "ERA()")
	case .REF:
		addr := get_data(port).(Ref_Data).addr
		name := book.names[addr]
		fmt.sbprintf(sb, "@%v", name)
	case .VAR:
		got := enter(program, port)
		if got != port {
			serialize_port(program, book, got, sb)
		} else {
			addr := get_data(port).(Var_Data).addr
			fmt.sbprintf(sb, "v%d", addr)
		}
	case .NUM:
		type := get_data(port).(Num_Data).type
		addr := get_data(port).(Num_Data).addr
		value := program.nums[addr]
		switch type {
		case .Uint:
			fmt.sbprintf(sb, "%v", value)
		case .Int:
			fmt.sbprintf(sb, "%v", transmute(i32)value)
		case .Float:
			fmt.sbprintf(sb, "%v", transmute(f32)value)
		}
	case .OPE:
		type := get_data(port).(Op_Data).type
		addr := get_data(port).(Op_Data).addr

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

		pair := program.nodes[addr]
		serialize_port(program, book, pair.?.left, sb)
		fmt.sbprint(sb, ", ")
		serialize_port(program, book, pair.?.right, sb)
		fmt.sbprint(sb, ")")
	case:
		#partial switch port.tag {
		case .CON:
			fmt.sbprint(sb, "CON(")
		case .DUP:
			fmt.sbprint(sb, "DUP(")
		case .SWI:
			fmt.sbprint(sb, "SWI(")
		}
		addr := get_data(port).(Node_Data).addr
		pair := program.nodes[addr]
		serialize_port(program, book, pair.?.left, sb)
		fmt.sbprint(sb, ", ")
		serialize_port(program, book, pair.?.right, sb)
		fmt.sbprint(sb, ")")
	}
}
