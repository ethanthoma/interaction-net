package main

import "core:fmt"

Port :: struct {
	tag:  Term_Kind,
	data: union {
		Empty, // ERA
		Node_Address, // CON DUP
		Var_Address, // VAR
		Ref_Address, // REF
	},
}

Node_Address :: distinct u32
Ref_Address :: distinct u32
Var_Address :: distinct u32
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
				fmt.wprintf(fi.writer, "%v:", m.tag)

				switch data in m.data {
				case Empty:
					fmt.wprint(fi.writer, "EMPTY")
				case Node_Address, Var_Address, Ref_Address:
					fmt.wprintf(fi.writer, "%5d", data)
				}
			case:
				return false
			}

			return true
		},
	)
}
