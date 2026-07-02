package main

import "base:runtime"
import "core:fmt"

Tag_Len :: 3
Tag_Mask :: 1 << Tag_Len - 1

Num_Type_Len :: 2
Num_Type_Mask :: 1 << Num_Type_Len - 1

Op_Type_Len :: 4
Op_Type_Mask :: 1 << Op_Type_Len - 1

Addr_Len :: 32 - Tag_Len - max(Num_Type_Len, Op_Type_Len)

Tag :: enum u8 {
	VAR,
	ERA,
	REF,
	NUM,
	CON,
	DUP,
	OPE,
	SWI,
}

// A Port packs a Tag into the low Tag_Len bits and a payload above them. The
// payload is an arena address, except NUM/OPE carry a Num_Type/Op_Type between
// the tag and the address. Plain shifts, NOT a bit_field: Odin lowers unaligned
// bit_field access through runtime.__read_bits/__write_bits, which loop per bit
// and measured as ~half of all reduction instructions (docs/perf-baseline.md).
Port :: distinct u32

Pair :: struct {
	left, right: Port,
}

make_port :: #force_inline proc "contextless" (tag: Tag, data: u32) -> Port {
	return Port(u32(tag) | data << Tag_Len)
}

port_tag :: #force_inline proc "contextless" (port: Port) -> Tag {
	return Tag(u32(port) & Tag_Mask)
}

port_data :: #force_inline proc "contextless" (port: Port) -> u32 {
	return u32(port) >> Tag_Len
}

// Address payload of VAR, REF, CON, DUP, and SWI ports.
port_addr :: #force_inline proc "contextless" (port: Port) -> int {
	return int(u32(port) >> Tag_Len)
}

make_num_port :: #force_inline proc "contextless" (type: Num_Type, addr: int) -> Port {
	return Port(u32(Tag.NUM) | u32(type) << Tag_Len | u32(addr) << (Tag_Len + Num_Type_Len))
}

num_type :: #force_inline proc "contextless" (port: Port) -> Num_Type {
	return Num_Type(u32(port) >> Tag_Len & Num_Type_Mask)
}

num_addr :: #force_inline proc "contextless" (port: Port) -> int {
	return int(u32(port) >> (Tag_Len + Num_Type_Len))
}

make_op_port :: #force_inline proc "contextless" (type: Op_Type, addr: int) -> Port {
	return Port(u32(Tag.OPE) | u32(type) << Tag_Len | u32(addr) << (Tag_Len + Op_Type_Len))
}

op_type :: #force_inline proc "contextless" (port: Port) -> Op_Type {
	return Op_Type(u32(port) >> Tag_Len & Op_Type_Mask)
}

op_addr :: #force_inline proc "contextless" (port: Port) -> int {
	return int(u32(port) >> (Tag_Len + Op_Type_Len))
}

Num_Type :: enum u8 {
	Uint,
	Int,
	Float,
}

Num_Value :: union {
	u32,
	i32,
	f32,
}

Op_Type :: enum u8 {
	Add,
	Sub,
	Mul,
	Div,
	Rem,
	Eq,
	Neq,
	Lt,
	Gt,
	And,
	Or,
	Xor,
	Shr,
	Shl,
}

@(private = "file", init)
fmt_port :: proc "contextless" () {
	context = runtime.default_context()
	if fmt._user_formatters == nil do fmt.set_user_formatters(new(map[typeid]fmt.User_Formatter))

	fmt.register_user_formatter(
		type_info_of(Port).id,
		proc(fi: ^fmt.Info, arg: any, verb: rune) -> bool {
			m := cast(^Port)arg.data

			switch verb {
			case 'v', 'd':
				tag := port_tag(m^)
				fmt.wprintf(fi.writer, "%v", tag)

				switch tag {
				case .ERA:
					fmt.wprint(fi.writer, "      ")
				case .VAR:
					if verb == 'v' && port_data(m^) == ROOT {
						fmt.wprintf(fi.writer, ": ROOT")
					} else {
						fmt.wprintf(fi.writer, ":%5d", port_addr(m^))
					}
				case .REF:
					if verb == 'v' && port_data(m^) == MAIN {
						fmt.wprintf(fi.writer, ": MAIN")
					} else {
						fmt.wprintf(fi.writer, ":%5d", port_addr(m^))
					}
				case .CON, .DUP, .SWI:
					fmt.wprintf(fi.writer, ":%5d", port_addr(m^))
				case .NUM:
					fmt.wprintf(fi.writer, ":%5d", num_addr(m^))
				case .OPE:
					fmt.wprintf(fi.writer, ":%5d", op_addr(m^))
				}
			case:
				return false
			}

			return true
		},
	)
}
