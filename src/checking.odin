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
}

check :: proc(defs: map[string]Definition) -> (err: Check_Error) {
	ctx := Context {
		definition_names = make(map[string]bool),
		variable_count   = make(map[string]int),
	}
	defer delete(ctx.definition_names)
	defer delete(ctx.variable_count)

	if "root" not_in defs do return .No_Root

	for name in defs {
		ctx.definition_names[name] = true
	}

	for _, &def in defs {
		check_definition(&def, &ctx) or_return
		clear(&ctx.variable_count)
	}

	return .None
}

@(private = "file")
check_definition :: proc(def: ^Definition, ctx: ^Context) -> (err: Check_Error) {
	check_term(def.root, ctx) or_return

	for redex in def.redexes {
		check_term(redex.left, ctx) or_return
		check_term(redex.right, ctx) or_return
	}

	check_linearity(def, ctx) or_return

	return .None
}

@(private = "file")
check_term :: proc(term: ^Term, ctx: ^Context) -> (err: Check_Error) {
	switch term.kind {
	case .VAR:
		name := term.data.(Var_Data).name
		ctx.variable_count[name] += 1
		if ctx.variable_count[name] > 2 {
			return .Non_Linear_Variable
		}
	case .ERA:
	case .REF:
		name := term.data.(Var_Data).name
		if name not_in ctx.definition_names {
			return .Unbound_Reference
		}
	case .CON, .DUP:
		node_data := term.data.(Node_Data)
		check_term(node_data.left, ctx) or_return
		check_term(node_data.right, ctx) or_return
	}

	return .None
}

@(private = "file")
check_linearity :: proc(def: ^Definition, ctx: ^Context) -> (err: Check_Error) {
	for var, count in ctx.variable_count {
		if count != 2 {
			fmt.printfln("Var %v had %d occurances", var, count)
			return .Non_Linear_Variable
		}
	}

	return .None
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

	tokenize(&tokenizer)

	parser := make_parser(tokenizer.tokens[:])
	defer delete_parser(&parser)

	testing.expect(t, parse(&parser), "Parser should succeed")

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

	tokenize(&tokenizer)

	parser := make_parser(tokenizer.tokens[:])
	defer delete_parser(&parser)

	testing.expect(t, parse(&parser), "Parser should succeed")

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
        @root := a & CON(b, c) ~ DUP(b, a)
    `

	tokenizer := make_tokenizer(input)
	defer delete_tokenizer(&tokenizer)

	tokenize(&tokenizer)

	parser := make_parser(tokenizer.tokens[:])
	defer delete_parser(&parser)

	testing.expect(t, parse(&parser), "Parser should succeed")

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
        @root := a & @first ~ CON(ERA(), a)
    `

	tokenizer := make_tokenizer(input)
	defer delete_tokenizer(&tokenizer)

	tokenize(&tokenizer)

	parser := make_parser(tokenizer.tokens[:])
	defer delete_parser(&parser)

	testing.expect(t, parse(&parser), "Parser should succeed")

	err := check(parser.definitions)

	testing.expectf(
		t,
		err == .Unbound_Reference,
		"Expected %v, got %v",
		Check_Error.Unbound_Reference,
		err,
	)
}
