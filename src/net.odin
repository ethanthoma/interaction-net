package main

import "core:fmt"

Term_Kind :: enum {
	VAR,
	ERA,
	REF,
	NUM,
	CON,
	DUP,
	OPE,
	SWI,
}

Port :: struct {
	tag:  Term_Kind,
	data: union {
		Empty, // ERA
		Node_Address, // CON DUP OPE SWI
		Var_Address, // VAR
		Ref_Address, // REF
		Num_Address, // NUM
	},
}

Node_Address :: distinct u32
Ref_Address :: distinct u32
Var_Address :: distinct u32
Num_Address :: distinct u32
// 4 bits
Ope_Type :: enum {
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
Empty :: struct {}

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

				switch data in m.data {
				case Empty:
					fmt.wprint(fi.writer, "      ")
				case Var_Address:
					if int(data) == int(ROOT) {
						fmt.wprintf(fi.writer, ": ROOT")
					} else {
						fmt.wprintf(fi.writer, ":%5d", data)
					}
				case Ref_Address:
					if int(data) == int(ROOT) {
						fmt.wprintf(fi.writer, ": MAIN")
					} else {
						fmt.wprintf(fi.writer, ":%5d", data)
					}
				case Node_Address:
					fmt.wprintf(fi.writer, ":%5d", data)
				case Num_Address:
					addr := (data >> 2) & 0x3FFF
					fmt.wprintf(fi.writer, ":%5d", addr)
				}
			case 'd':
				fmt.wprintf(fi.writer, "%v", m.tag)

				switch data in m.data {
				case Empty:
					fmt.wprint(fi.writer, "      ")
				case Var_Address, Ref_Address, Node_Address:
					fmt.wprintf(fi.writer, ":%5d", data)
				case Num_Address:
					addr := (data >> 2) & 0x3FFF
					fmt.wprintf(fi.writer, ":%5d", addr)
				}
			case:
				return false
			}

			return true
		},
	)
}
