package main

import "core:fmt"
import "core:testing"

Check_Error :: enum {
	None,
	No_Root,
	Non_Linear_Variable,
	Unbound_Reference,
}

@(private = "file")
Context :: struct {
	definition_names: map[string]bool,
	variable_count:   map[string]int,
	def_name:         string,
}

check :: proc(defs: map[string]Definition) -> (err: Check_Error) {
	ctx := Context {
		definition_names = make(map[string]bool),
		variable_count   = make(map[string]int),
	}
	defer delete(ctx.definition_names)
	defer delete(ctx.variable_count)
	context.user_ptr = &ctx

	if "root" not_in defs {
		error("no root definition")
		return .No_Root
	}

	for name in defs {
		ctx.definition_names[name] = true
	}

	for _, &def in defs {
		ctx.def_name = def.name
		check_definition(&def) or_return
		clear(&ctx.variable_count)
	}

	return .None
}

@(private = "file")
check_definition :: proc(def: ^Definition) -> (err: Check_Error) {
	check_term(def.root) or_return

	for redex in def.redexes {
		check_term(redex.left) or_return
		check_term(redex.right) or_return
	}

	check_linearity(def) or_return

	return .None
}

@(private = "file")
check_term :: proc(term: ^Term) -> (err: Check_Error) {
	ctx := cast(^Context)context.user_ptr
	switch term.kind {
	case .VAR:
		name := term.data.(Var_Data).name
		ctx.variable_count[name] += 1
		if ctx.variable_count[name] > 2 {
			error(
				"def @%s: variable %s referenced more than twice in a definition",
				ctx.def_name,
				name,
			)
			return .Non_Linear_Variable
		}
	case .ERA:
	case .REF:
		name := term.data.(Var_Data).name
		if name not_in ctx.definition_names {
			error(
				"def @%s: reference @%s is not defined at %d:%d",
				ctx.def_name,
				name,
				term.pos.line,
				term.pos.column,
			)
			return .Unbound_Reference
		}
	case .CON, .DUP:
		node_data := term.data.(Node_Data)
		check_term(node_data.left) or_return
		check_term(node_data.right) or_return
	}

	return .None
}

@(private = "file")
check_linearity :: proc(def: ^Definition) -> (err: Check_Error) {
	ctx := cast(^Context)context.user_ptr
	for var, count in ctx.variable_count {
		if count != 2 {
			error("@def %s: variable %s has %d references, expected 2", def.name, var, count)
			return .Non_Linear_Variable
		}
	}

	return .None
}

@(private = "file")
error :: proc(msg: string, args: ..any) {
	fmt.eprintf("Check: ")
	fmt.eprintf(msg, ..args)
	fmt.eprintf("\n")
}

// ** Testing **
@(test)
test_check_succeed :: proc(t: ^testing.T) {
	input := `
        @root = a 
            & CON(ERA(), DUP(c, CON(d, DUP(c, d)))) 
            ~ CON(a, DUP(e, CON(b, DUP(e, b))))
    `

	tokenizer := make_tokenizer(input)
	defer delete_tokenizer(&tokenizer)

	tokens, token_ok := tokenize(&tokenizer)
	testing.expect(t, token_ok, "Tokenizing should succeed")

	parser := make_parser(tokens)
	defer delete_parser(&parser)

	definitions, parse_ok := parse(&parser)

	testing.expect(t, parse_ok, "Parsing should succeed")

	err := check(parser.definitions)

	testing.expectf(t, err == .None, "Expected %v, got %v", Check_Error.None, err)
}

@(test)
test_check_non_linear_variable_one :: proc(t: ^testing.T) {
	input := `
        @root = a
    `

	tokenizer := make_tokenizer(input)
	defer delete_tokenizer(&tokenizer)

	tokens, token_ok := tokenize(&tokenizer)
	testing.expect(t, token_ok, "Tokenizing should succeed")

	parser := make_parser(tokens)
	defer delete_parser(&parser)

	definitions, parse_ok := parse(&parser)

	testing.expect(t, parse_ok, "Parsing should succeed")

	err := check(parser.definitions)

	testing.expectf(
		t,
		err == .Non_Linear_Variable,
		"Expected %v, got %v",
		Check_Error.Non_Linear_Variable,
		err,
	)
}


@(test)
test_check_non_linear_variable_three :: proc(t: ^testing.T) {
	input := `
        @root = a & CON(b, c) ~ DUP(b, a)
    `

	tokenizer := make_tokenizer(input)
	defer delete_tokenizer(&tokenizer)

	tokens, token_ok := tokenize(&tokenizer)
	testing.expect(t, token_ok, "Tokenizing should succeed")

	parser := make_parser(tokens)
	defer delete_parser(&parser)

	definitions, parse_ok := parse(&parser)

	testing.expect(t, parse_ok, "Parsing should succeed")

	err := check(parser.definitions)

	testing.expectf(
		t,
		err == .Non_Linear_Variable,
		"Expected %v, got %v",
		Check_Error.Non_Linear_Variable,
		err,
	)
}

@(test)
test_check_Unbound_Reference :: proc(t: ^testing.T) {
	input := `
        @root = a & @first ~ CON(ERA(), a)
    `

	tokenizer := make_tokenizer(input)
	defer delete_tokenizer(&tokenizer)

	tokens, token_ok := tokenize(&tokenizer)
	testing.expect(t, token_ok, "Tokenizing should succeed")

	parser := make_parser(tokens)
	defer delete_parser(&parser)

	definitions, parse_ok := parse(&parser)

	testing.expect(t, parse_ok, "Parsing should succeed")

	err := check(parser.definitions)

	testing.expectf(
		t,
		err == .Unbound_Reference,
		"Expected %v, got %v",
		Check_Error.Unbound_Reference,
		err,
	)
}
