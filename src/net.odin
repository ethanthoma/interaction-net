package main

import "core:fmt"

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

Port :: bit_field u32 {
	tag:  Tag | 3,
	data: u32 | 29,
}

get_data :: proc(port: Port) -> Data {
	switch port.tag {
	case .VAR:
		return transmute(Var_Data)port.data
	case .ERA:
		return transmute(Empty)port.data
	case .REF:
		return transmute(Ref_Data)port.data
	case .NUM:
		return transmute(Num_Data)port.data
	case .CON, .DUP, .SWI:
		return transmute(Node_Data)port.data
	case .OPE:
		return transmute(Op_Data)port.data
	}

	return nil
}

Data :: union {
	Empty, // ERA
	Var_Data, // VAR
	Ref_Data, // REF
	Node_Data, // CON DUP SWI
	Num_Data, // NUM
	Op_Data, // OPE
}

Var_Data :: bit_field u32 {
	addr: int | 29,
}

Empty :: distinct u32

Node_Data :: bit_field u32 {
	addr: int | 29,
}

Ref_Data :: bit_field u32 {
	addr: int | 29,
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

Num_Data :: bit_field u32 {
	type: Num_Type | 2,
	addr: int      | 29 - 2,
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

Op_Data :: bit_field u32 {
	type: Op_Type | 4,
	addr: int     | 29 - 4,
}

Pair :: struct {
	left, right: Port,
}

@(private = "file", init)
fmt_port :: proc() {
	if fmt._user_formatters == nil do fmt.set_user_formatters(new(map[typeid]fmt.User_Formatter))

	err := fmt.register_user_formatter(
		type_info_of(Port).id,
		proc(fi: ^fmt.Info, arg: any, verb: rune) -> bool {
			m := cast(^Port)arg.data

			switch verb {
			case 'v':
				fmt.wprintf(fi.writer, "%v", m.tag)

				switch data in get_data(m^) {
				case Empty:
					fmt.wprint(fi.writer, "      ")
				case Var_Data:
					if int(data) == int(ROOT) {
						fmt.wprintf(fi.writer, ": ROOT")
					} else {
						fmt.wprintf(fi.writer, ":%5d", data.addr)
					}
				case Ref_Data:
					if int(data) == int(ROOT) {
						fmt.wprintf(fi.writer, ": MAIN")
					} else {
						fmt.wprintf(fi.writer, ":%5d", data.addr)
					}
				case Node_Data:
					fmt.wprintf(fi.writer, ":%5d", data.addr)
				case Num_Data:
					fmt.wprintf(fi.writer, ":%5d", data.addr)
				case Op_Data:
					fmt.wprintf(fi.writer, ":%5d", data.addr)
				}
			case 'd':
				fmt.wprintf(fi.writer, "%v", m.tag)

				switch data in get_data(m^) {
				case Empty:
					fmt.wprint(fi.writer, "      ")
				case Var_Data:
					fmt.wprintf(fi.writer, ":%5d", data.addr)
				case Ref_Data:
					fmt.wprintf(fi.writer, ":%5d", data.addr)
				case Op_Data:
					fmt.wprintf(fi.writer, ":%5d", data.addr)
				case Node_Data:
					fmt.wprintf(fi.writer, ":%5d", data.addr)
				case Num_Data:
					fmt.wprintf(fi.writer, ":%5d", data.addr)
				}
			case:
				return false
			}

			return true
		},
	)
}
