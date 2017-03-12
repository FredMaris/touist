(** Functions for semantic analysis of the abstract syntaxic tree produced by [Parse.parse].
    
    [eval] is the main function. *)

(* Project TouIST, 2015. Easily formalize and solve real-world sized problems
 * using propositional logic and linear theory of reals with a nice language and GUI.
 *
 * https://github.com/touist/touist
 *
 * Copyright Institut de Recherche en Informatique de Toulouse, France
 * This program and the accompanying materials are made available
 * under the terms of the GNU Lesser General Public License (LGPL)
 * version 2.1 which accompanies this distribution, and is available at
 * http://www.gnu.org/licenses/lgpl-2.1.html 
 *)

open Syntax
open Pprint
open Msg


(* Variables are stored in two data structures (global and local scopes). *)

(* [env] is for local variables (for bigand,bigor and let constructs).
   It is a simple list [(name,description),...] passed as recursive argument.
   The name is the variable name (e.g., '$var' or '$var(a,1,c)').
   The description is a couple (content, location) *)
type env = (string * (ast * loc)) list

(* [extenv] is for global variables (defined after 'data'). It is a hashtable
   accessible from anywhere where the elements are (name, description):
   The name is the variable name (e.g., '$var' or '$var(a,1,c)').
   The description is a couple (content, location) *)
type extenv = (string, (ast * loc)) Hashtbl.t

let warning (ast:ast) (message:string) =
  let loc = match ast with 
    | Loc (_,loc) -> loc 
    | _ -> (Lexing.dummy_pos,Lexing.dummy_pos)
  in add_msg (Warning,Eval,message,loc)

(* [ast_whithout_loc] removes the location attached by the parser to the ast
   node. This location 'Loc (ast,loc)' allows to give the location in error 
   messages. [ast_whithout_loc] must be called before any 
        match ast with | Inter (x,y) -> ... *)
let ast_whithout_loc (ast:ast) : ast = match ast with
  | Loc (ast,_) -> ast
  | ast -> ast

(* [raise_with_loc] takes an ast that may contains a Loc (Loc is added in
   parser.mly) and raise an exception with the given message.
   The only purpose of giving 'ast' is to get the Loc thing.
   [ast_whithout_loc] should not have been previously applied to [ast]
   because ast_whithout_loc will remove the Loc thing. *)
let raise_with_loc (ast:ast) (message:string) = match ast with
  | Loc (ast,loc) -> add_fatal (Error,Eval,message,loc)
  | _ -> add_fatal (Error,Eval,message,(Lexing.dummy_pos,Lexing.dummy_pos))

(* [raise_type_error] raises the errors that come from one-parameter functions.
   operator is the non-expanded (expand = eval_ast) operator.
   Example: in 'To_int x', 'operand' is the non-expanded parameter 'x',
   'expanded' is the expanded parameter 'x'.
   Expanded means that eval_ast has been applied to x.
   [expected_types] contain a string that explain what is expected, e.g.,
   'an integer or a float'. *)
let raise_type_error operator operand expanded (expected_types:string) = 
  raise_with_loc operator (
    "'"^(string_of_ast_type operator)^"' expects "^expected_types^".\n"^
    "The operand:\n"^
    "    "^(string_of_ast operand)^"\n"^
    "has been expanded to something of type '"^(string_of_ast_type expanded)^"':\n"^
    "    "^(string_of_ast expanded)^"")

(* Same as above but for functions of two parameters. Example: with And (x,y),
   operator is And (x,y),
   op1 and op2 are the non-expanded parameters x and y,
   exp1 and exp2 are the expanded parameters x and y. *)
let raise_type_error2 operator op1 exp1 op2 exp2 (expected_types:string) =
  raise_with_loc operator
    ("incorrect types with '"^(string_of_ast_type operator)^"'; expects "^expected_types^".\n"^
    "In statement:\n"^
    "    "^(string_of_ast operator)^"\n"^
    "Left-hand operand has type '"^(string_of_ast_type exp1)^"':\n"^
    "    "^(string_of_ast exp1)^"\n"^
    "Right-hand operand has type '"^(string_of_ast_type exp2)^"':\n"^
    "    "^(string_of_ast exp2)^""^
    "")

(* [raise_set_decl] is the same as [raise_type_error2] but between one element
   and the set this element is supposed to be added to. *)
let raise_set_decl ast elmt elmt_expanded set set_expanded (expected_types:string) =
  raise_with_loc ast
    ("Ill-formed set declaration. It expects "^expected_types^".\n"^
    "One of the elements is of type '"^(string_of_ast_type elmt_expanded)^"':\n"^
    "    "^(string_of_ast elmt)^"\n"^
    "This element has been expanded to\n"^
    "    "^(string_of_ast elmt_expanded)^"\n"^
    "Up to now, the set declaration\n"^
    "    "^(string_of_ast set)^"\n"^
    "has been expanded to:\n"^
    "    "^(string_of_ast set_expanded)^"")


let check_nb_vars_same_as_nb_sets (ast:ast) (vars: ast list) (sets: ast list) : unit =
  let loc = match (List.nth vars 0), List.nth sets ((List.length sets)-1) with
    | Loc (_,(startpos,_)), Loc (_,(_,endpos)) -> startpos,endpos 
    | _-> failwith "[shouldn't happen] missing locations in vars/sets"
  in
  match (List.length vars) == (List.length sets) with
  | true -> ()
  | false -> add_fatal (Error,Eval,
    "Ill-formed '"^(string_of_ast_type ast)^"'. The number of variables and sets must be the same.\n"^
    "You defined "^(string_of_int (List.length vars))^" variables:\n"^
    "    "^(string_of_ast_list "," vars)^"\n"^
    "but you gave "^(string_of_int (List.length sets))^" sets:\n"^
    "    "^(string_of_ast_list "," sets)^""
    ,loc)


(* [process_empty] is necessary because of how 'clunky' have been implemented
   the set capabilities (type 'set', EmptySet, ISet, IntSet.empty.....).
   If 'set' is EmptySet, transform it into a typed IntSet.empty,
   FloatSet.empty or PropSet.empty, depending on the type of 'set_type'.
   If 'set' isn't an empty set, then return 'set'.*)
let process_empty (set:ast) (set_type:ast) : ast = match set,set_type with
  | Set EmptySet, Set (ISet _) -> Set (ISet IntSet.empty)
  | Set EmptySet, Set (FSet _) -> Set (FSet FloatSet.empty)
  | Set EmptySet, Set (SSet _) -> Set (SSet PropSet.empty)
  | Set EmptySet, Set (EmptySet)  -> Set (ISet IntSet.empty) (* arbitrary *)
  | _,_ -> set

let extenv = ref (Hashtbl.create 0)
let check_only = ref false

(* [check_only] allows to only 'check the types'. It prevents the bigand,
    bigor, exact, atmost, atleast and range to expand completely(as it
    may take a lot of time to do so). *)
let check_only = ref false

(* By default, we are in 'SAT' mode. When [smt] is true,
   some type checking (variable expansion mostly) is different
   (formulas can be 'int' or 'float' for example). *)
let smt = ref false

(** Main function for checking the types and evaluating the touistl expressions
    (variables, bigand, bigor, let...).

    @param ast is the AST given by [Parse.parse] 
    @param onlychecktypes will limit the evaluation to its minimum in
           order to get type errors as fast as possible.
    @param smt enables the SMT mode. By default, the SAT mode is used.

    @raise Eval.Error (msg,loc) *)
let rec eval ?smt:(smt_mode=false) ?(onlychecktypes=false) ast =
  check_only := onlychecktypes;
  smt := smt_mode;
  extenv := Hashtbl.create 50; (* extenv must be re-init between two calls to [eval] *)
  eval_touist_code ast []

and eval_touist_code ast (env:env) =
  let rec affect_vars = function
    | [] -> []
    | Loc (Affect (Loc (Var (p,i),var_loc),y),affect_loc)::xs ->
      Hashtbl.replace !extenv (expand_var_name (p,i) env) (eval_ast y env, var_loc);
        affect_vars xs
    | x::xs -> x::(affect_vars xs)
  in
  let rec process_formulas = function
    | []    -> raise_with_loc ast ("no formulas")
    | x::[] -> x
    | x::xs -> And (x, process_formulas xs)
  in
  match ast_whithout_loc ast with
  | Touist_code (formulas) ->
    eval_ast_formula (process_formulas (affect_vars formulas)) env
  | e -> raise_with_loc ast ("this does not seem to be a touist code structure: " ^ string_of_ast e)

(* [eval_ast] evaluates (= expands) numerical, boolean and set expresions that
   are not directly in formulas. For example, in 'when $a!=a' or 'if 3>4',
   the boolean values must be computed: eval_ast will do exactly that.*)
and eval_ast (ast:ast) (env:env) = match ast_whithout_loc ast with
  | Int x   -> Int x
  | Float x -> Float x
  | Bool x  -> Bool x
  | Var (p,i) -> (* p,i = prefix, indices *)
    let name = expand_var_name (p,i) env in
    begin
      try let (content,loc) = List.assoc name env in content
      with Not_found ->
      try let (content,_) = Hashtbl.find !extenv name in content
      with Not_found -> raise_with_loc ast
          ("variable '" ^ name ^"' does not seem to be known. Either you forgot\n"^
          "to declare it globally or it has been previously declared locally\n"^
          "(with bigand, bigor or let) and you are out of its scope.")
    end
  | Set x -> Set x
  | Set_decl x -> eval_set_decl ast env
  | Neg x -> (match eval_ast x env with
      | Int x'   -> Int   (- x')
      | Float x' -> Float (-. x')
      | x' -> raise_type_error ast x x' "'float' or 'int'")
  | Add (x,y) -> (match eval_ast x env, eval_ast y env with
      | Int x, Int y -> Int (x + y)
      | Float x, Float y -> Float (x +. y)
      | x',y' -> raise_type_error2 ast x x' y y' "'float' or 'int'")
  | Sub (x,y) -> (match eval_ast x env, eval_ast y env with
      | Int x, Int y -> Int (x - y)
      | Float x, Float y -> Float (x -. y)
      | x',y' -> raise_type_error2 ast x x' y y' "'float' or 'int'")
  | Mul (x,y) -> (match eval_ast x env, eval_ast y env with
      | Int x, Int y -> Int (x * y)
      | Float x, Float y -> Float (x *. y)
      | x',y' -> raise_type_error2 ast x x' y y' "a 'float' or 'int'")
  | Div (x,y) -> (match eval_ast x env, eval_ast y env with
      | Int x, Int y -> Int (x / y)
      | Float x, Float y -> Float (x /. y)
      | x',y' -> raise_type_error2 ast x x' y y' "a 'float' or 'int'")
  | Mod (x,y) -> (match eval_ast x env, eval_ast y env with
      | Int x, Int y -> Int (x mod y)
      | x',y' -> raise_type_error2 ast x x' y y' "a 'float' or 'int'")
  | Sqrt x -> (match eval_ast x env with
      | Float x -> Float (sqrt x)
      | x' -> raise_type_error ast x x' "a float")
  | To_int x -> (match eval_ast x env with
      | Float x -> Int (int_of_float x)
      | Int x   -> Int x
      | x' -> raise_type_error ast x x' "a 'float' or 'int'")
  | To_float x -> (match eval_ast x env with
      | Int x   -> Float (float_of_int x)
      | Float x -> Float x
      | x' -> raise_type_error ast x x' "a 'float' or 'int'")
  | Abs x -> (match eval_ast x env with
      | Int x   -> Int (abs x)
      | Float x -> Float (abs_float x)
      | x' -> raise_type_error ast x x' "a 'float' or 'int'")
  | Not x -> (match eval_ast x env with
      | Bool x -> Bool (not x)
      | x' -> raise_type_error ast x x' "a 'bool'")
  | And (x,y) -> (match eval_ast x env, eval_ast y env with
      | Bool x,Bool y -> Bool (x && y)
      | x',y' -> raise_type_error2 ast x x' y y' "a 'bool'")
  | Or (x,y) -> (match eval_ast x env, eval_ast y env with
      | Bool x,Bool y -> Bool (x || y)
      | x',y' -> raise_type_error2 ast x x' y y' "a 'bool'")
  | Xor (x,y) -> (match eval_ast x env, eval_ast y env with
      | Bool x,Bool y -> Bool ((x || y) && (not (x && y)))
      | x',y' -> raise_type_error2 ast x x' y y' "a 'bool'")
  | Implies (x,y) -> (match eval_ast x env, eval_ast y env with
      | Bool x,Bool y -> Bool (not x || y)
      | x',y' -> raise_type_error2 ast x x' y y' "a 'bool'")
  | Equiv (x,y) -> (match eval_ast x env, eval_ast y env with
      | Bool x,Bool y -> Bool ((not x || y) && (not x || y))
      | x',y' -> raise_type_error2 ast x x' y y' "a 'bool'")
  | If (x,y,z) ->
    let test =
      match eval_ast x env with
      | Bool true  -> true
      | Bool false -> false
      | x' -> raise_type_error ast x x' "a 'bool'"
    in
    if test then eval_ast y env else eval_ast z env
  | Union (x,y) -> begin
      let x',y' = eval_ast x env, eval_ast y env in
      match process_empty x' y', process_empty y' x' with
      | Set (ISet a), Set (ISet b) -> Set (ISet (IntSet.union a b))
      | Set (FSet a), Set (FSet b) -> Set (FSet (FloatSet.union a b))
      | Set (SSet a), Set (SSet b) -> Set (SSet (PropSet.union a b))
      | _,_ -> raise_type_error2 ast x x' y y' "a 'float-set', 'int-set' or 'prop-set'"
    end
  | Inter (x,y) -> begin
      let x',y' = eval_ast x env, eval_ast y env in
      match process_empty x' y', process_empty y' x' with
      | Set (ISet a), Set (ISet b) -> Set (ISet (IntSet.inter a b))
      | Set (FSet a), Set (FSet b) -> Set (FSet (FloatSet.inter a b))
      | Set (SSet a), Set (SSet b) -> Set (SSet (PropSet.inter a b))
      | _,_ -> raise_type_error2 ast x x' y y' "a 'float-set', 'int-set' or 'prop-set'"
    end
  | Diff (x,y) -> begin
      let x',y' = eval_ast x env, eval_ast y env in
      match process_empty x' y', process_empty y' x' with
      | Set (ISet a), Set (ISet b) -> Set (ISet (IntSet.diff a b))
      | Set (FSet a), Set (FSet b) -> Set (FSet (FloatSet.diff a b))
      | Set (SSet a), Set (SSet b) -> Set (SSet (PropSet.diff a b))
      | _,_ -> raise_type_error2 ast x x' y y' "a 'float-set', 'int-set' or 'prop-set'"
    end
  | Range (x,y) -> (* !check_only will simplify [min..max] to [min..min] *)
    (* [irange] generates a list of int between min and max with an increment of step. *)
    let irange min max step =
      let rec loop acc = function i when i=max+1 -> acc | i -> loop (i::acc) (i+step)
      in loop [] min |> List.rev
    and frange min max step =
      let rec loop acc = function i when i=max+.1. -> acc | i -> loop (i::acc) (i+.step)
      in loop [] min |> List.rev
    in begin
      match eval_ast x env, eval_ast y env with
      | Int x, Int y     -> Set (ISet (IntSet.of_list (irange x (if !check_only then x else y)  1)))
      | Float x, Float y -> Set (FSet (FloatSet.of_list (frange x (if !check_only then x else y) 1.)))
      | x',y' -> raise_type_error2 ast x x' y y' "two integers or two floats"
    end
  | Empty x -> begin
      match eval_ast x env with
      | Set (EmptySet)    -> Bool true
      | Set (ISet x) -> Bool (IntSet.is_empty x)
      | Set (FSet x) -> Bool (FloatSet.is_empty x)
      | Set (SSet x) -> Bool (PropSet.is_empty x)
      | x' -> raise_type_error ast x x' "a 'float-set', 'int-set' or 'prop-set'"
    end
  | Card x -> begin
      match eval_ast x env with
      | Set (EmptySet)    -> Int 0
      | Set (ISet x) -> Int (IntSet.cardinal x)
      | Set (FSet x) -> Int (FloatSet.cardinal x)
      | Set (SSet x) -> Int (PropSet.cardinal x)
      | x' -> raise_type_error ast x x' "a 'float-set', 'int-set' or 'prop-set'"
    end
  | Subset (x,y) -> begin
      let x',y' = eval_ast x env, eval_ast y env in
      match process_empty x' y', process_empty y' x' with
      | Set (ISet a), Set (ISet b) -> Bool (IntSet.subset a b)
      | Set (FSet a), Set (FSet b) -> Bool (FloatSet.subset a b)
      | Set (SSet a), Set (SSet b) -> Bool (PropSet.subset a b)
      | _,_ -> raise_type_error2 ast x x' y y' "a 'float-set', int or prop"
    end
  | In (x,y) ->
    begin match eval_ast x env, eval_ast y env with
      | _, Set (EmptySet) -> Bool false (* nothing can be in an empty set!*)
      | Int x, Set (ISet y) -> Bool (IntSet.mem x y)
      | Float x', Set (FSet y') -> Bool (FloatSet.mem x' y')
      | Prop x', Set (SSet y') -> Bool (PropSet.mem x' y')
      | x',y' -> raise_type_error2 ast x x' y y' "\nan 'int', 'float' or 'prop' on the left-hand and a 'set' on the right-hand"
    end
  | Equal (x,y) -> begin let x',y' = eval_ast x env, eval_ast y env in
      match process_empty x' y', process_empty y' x' with
      | Int x, Int y -> Bool (x = y)
      | Float x, Float y -> Bool (x = y)
      | Prop x, Prop y -> Bool (x = y)
      | Set (ISet a), Set (ISet b) -> Bool (IntSet.equal a b)
      | Set (FSet a), Set (FSet b) -> Bool (FloatSet.equal a b)
      | Set (SSet a), Set (SSet b) -> Bool (PropSet.equal a b)
      | x',y' -> raise_type_error2 ast x x' y y' "an int, float, prop or set"
    end
  | Not_equal (x,y) -> eval_ast (Not (Equal (x,y))) env
  | Lesser_than (x,y) -> (match eval_ast x env, eval_ast y env with
      | Int x, Int y -> Bool (x < y)
      | Float x, Float y -> Bool (x < y)
      | x',y' -> raise_type_error2 ast x x' y y' "a 'float' or 'int'")
  | Lesser_or_equal (x,y) -> (match eval_ast x env, eval_ast y env with
      | Int x, Int y -> Bool (x <= y)
      | Float x, Float y -> Bool (x <= y)
      | x',y' -> raise_type_error2 ast x x' y y' "a 'float' or 'int'")
  | Greater_than     (x,y) -> (match eval_ast x env, eval_ast y env with
      | Int x, Int y -> Bool (x > y)
      | Float x, Float y -> Bool (x > y)
      | x',y' -> raise_type_error2 ast x x' y y' "a 'float' or 'int'")
  | Greater_or_equal (x,y) -> (match eval_ast x env, eval_ast y env with
      | Int x, Int y -> Bool (x >= y)
      | Float x, Float y -> Bool (x >= y)
      | x',y' -> raise_type_error2 ast x x' y y' "a 'float' or 'int'")
  | UnexpProp (p,i) -> expand_prop_with_set p i env
  | Prop x -> Prop x
  | Loc (x,l) -> eval_ast x env
  | Paren x -> eval_ast x env
  | e -> raise_with_loc ast ("this expression cannot be expanded: " ^ string_of_ast e)

and eval_set_decl (set_decl:ast) (env:env) =
  let sets = (match ast_whithout_loc set_decl with Set_decl sets -> sets | _ -> failwith "shoulnt happen: non-Set_decl in eval_set_decl") in
  let sets_expanded = List.map (fun x -> eval_ast x env) sets in
  let unwrap_int elmt elmt_expanded = match elmt_expanded with
    | Int x -> x
    | _ -> raise_set_decl set_decl elmt elmt_expanded
             (Set_decl sets) (Set_decl sets_expanded)
             "at this point a\ncomma-separated list of integers, because previous elements\nof the list had this type"
  and unwrap_float elmt elmt_expanded = match elmt_expanded with
    | Float x -> x
    | _ -> raise_set_decl set_decl elmt elmt_expanded
             (Set_decl sets) (Set_decl sets_expanded)
             "at this point a\ncomma-separated list of floats, because previous elements\nof the list had this type"
  and unwrap_str elmt elmt_expanded = match elmt_expanded with
    | Prop x -> x
    | _ -> raise_set_decl set_decl elmt elmt_expanded
             (Set_decl sets) (Set_decl sets_expanded)
             "at this point a\ncomma-separated list of propositions, because previous elements\nof the list had this type"

  in (* this match-with uses the first element of the list to set the set type
        (ISet, FSet, SSet...)*)
  match sets, sets_expanded with
  | [],[] -> Set (EmptySet) (*   (fun -> function Int x->x   *)
  | _,(Int _)::_ -> Set (ISet (IntSet.of_list (List.map2 unwrap_int sets sets_expanded)))
  | _,(Float _)::_ -> Set (FSet (FloatSet.of_list (List.map2 unwrap_float sets sets_expanded)))
  | _,(Prop _)::_ -> Set (SSet (PropSet.of_list (List.map2 unwrap_str sets sets_expanded)))
  | x::_,x'::_ -> raise_set_decl set_decl x x'
                    (Set_decl sets) (Set_decl sets_expanded)
                    "elements of type int,\nfloat or propositon"
  | [],x::_ | x::_,[] -> failwith "shouldn't happen: len(sets)!=len(sets_expanded)" 


(* [eval_ast_formula] evaluates formulas; nothing in formulas should be
   expanded, except for variables, bigand, bigor, let, exact, atleast,atmost. *)
and eval_ast_formula (ast:ast) (env:env) : ast =
  match ast_whithout_loc ast with
  | Int x   -> Int x
  | Float x -> Float x
  | Neg x ->
    begin
      match eval_ast_formula x env with
      | Int   x' -> Int   (- x')
      | Float x' -> Float (-. x')
      | x' -> Neg x'
      (*| _ -> raise (Error (string_of_ast ast))*)
    end
  | Add (x,y) ->
    begin
      match eval_ast_formula x env, eval_ast_formula y env with
      | Int x', Int y'     -> Int   (x' +  y')
      | Float x', Float y' -> Float (x' +. y')
      | Int _, Prop _
      | Prop _, Int _ -> Add (x,y)
      | x', y' -> Add (x', y')
      (*| _,_ -> raise (Error (string_of_ast ast))*)
    end
  | Sub (x,y) ->
    begin
      match eval_ast_formula x env, eval_ast_formula y env with
      | Int x', Int y'     -> Int   (x' -  y')
      | Float x', Float y' -> Float (x' -. y')
      (*| Prop x', Prop x' -> Sub (Prop x', Prop x')*)
      | x', y' -> Sub (x', y')
      (*| _,_ -> raise (Error (string_of_ast ast))*)
    end
  | Mul (x,y) ->
    begin
      match eval_ast_formula x env, eval_ast_formula y env with
      | Int x', Int y'     -> Int   (x' *  y')
      | Float x', Float y' -> Float (x' *. y')
      | x', y' -> Mul (x', y')
      (*| _,_ -> raise (Error (string_of_ast ast))*)
    end
  | Div (x,y) ->
    begin
      match eval_ast_formula x env, eval_ast_formula y env with
      | Int x', Int y'     -> Int   (x' /  y')
      | Float x', Float y' -> Float (x' /. y')
      | x', y' -> Div (x', y')
      (*| _,_ -> raise (Error (string_of_ast ast))*)
    end
  | Equal            (x,y) -> Equal            (eval_ast_formula x env, eval_ast_formula y env)
  | Not_equal        (x,y) -> Not_equal        (eval_ast_formula x env, eval_ast_formula y env)
  | Lesser_than      (x,y) -> Lesser_than      (eval_ast_formula x env, eval_ast_formula y env)
  | Lesser_or_equal  (x,y) -> Lesser_or_equal  (eval_ast_formula x env, eval_ast_formula y env)
  | Greater_than     (x,y) -> Greater_than     (eval_ast_formula x env, eval_ast_formula y env)
  | Greater_or_equal (x,y) -> Greater_or_equal (eval_ast_formula x env, eval_ast_formula y env)
  | Top    -> Top
  | Bottom -> Bottom
  | UnexpProp (p,i) -> Prop (expand_var_name (p,i) env)
  | Prop x -> Prop x
  | Var (p,i) -> (* p,i = prefix,indices *)
    (* name = prefix + indices. 
       Example with $v(a,b,c):
       name is '$v(a,b,c)', prefix is '$v' and indices are '(a,b,c)' *)
    let name = expand_var_name (p,i) env in
    begin
      (* Case 1. Check if this variable name has been affected locally
         (recursive-wise) in bigand, bigor or let.
         To be accepted, this variable must contain a proposition. *)
      try let content,loc_affect = List.assoc name env in
        match content with
        | Prop x -> Prop x
        | Int x when !smt -> Int x
        | Float x when !smt -> Float x
        | _ -> raise_with_loc ast
            ("local variable '" ^ name ^ "' (defined in bigand, bigor or let)\n"^
            "cannot be expanded into a 'prop' because its content\n"^
            "is of type '"^(string_of_ast_type content)^"' instead of "^
              (if !smt then "'prop', 'int' or 'float'" else "'prop'") ^ ".\n"^
            "Why? Because this variable is part of a formula, and thus is expected\n"^
            "to be a proposition. Here is the content of '" ^name^"':\n"^
            "    "^(string_of_ast content))
      with Not_found ->
      (* Case 2. Check if this variable name has been affected globally, i.e.,
         in the 'data' section. To be accepted, this variable must contain
         a proposition. *)
      try let content,loc_affect = Hashtbl.find !extenv name in
        match content with
        | Prop x -> Prop x
        | Int x when !smt -> Int x
        | Float x when !smt -> Float x
        | _ -> raise_with_loc ast
            ("global variable '" ^ name ^ "' cannot be expanded into a 'prop'\n"^
            "because its content is of type '"^(string_of_ast_type content)^"' instead of "^
               (if !smt then "'prop', 'int' or 'float'" else "'prop'") ^ ".\n"^
            "Why? Because this variable is part of a formula, and thus is expected\n"^
            "to be a proposition. Here is the content of '" ^name^"':\n"^
            "    "^(string_of_ast content))
      with Not_found ->
      try
        match (p,i) with
        (* Case 3. The variable is a non-tuple of the form '$v' => name=prefix only.
           As it has not been found in the Case 1 or 2, this means that this variable
           has not been declared. *)
        | prefix, None -> raise Not_found (* trick to go to the Case 5. error *)
        (* Case 4. The var is a tuple-variable of the form '$v(1,2,3)' and has not
           been declared.
           But maybe we are in the following special case where the parenthesis
           in $v(a,b,c) that should let think it is a tuple-variable is actually
           a 'reconstructed' term, e.g. the content of $v should be expanded.
           Example of use:
            $F = [a,b,c]
            bigand $i in [1..3]:
              bigand $f in $F:     <- $f is defined as non-tuple variable (= no indices)
                $f($i)             <- here, $f looks like a tuple-variable but NO!
              end                     It is simply used to form the proposition
            end                       a(1), a(2)..., b(1)...    *)
        | prefix, Some indices ->
          let (content,loc_affect) = List.assoc prefix env in
          let term = match content with
            | Prop x -> Prop x
            | wrong -> add_fatal (Error,Eval,
                "the proposition '" ^ name ^ "' cannot be expanded because '"^prefix^"' is of type '"^(string_of_ast_type wrong)^"'.\n" ^
                "In order to produce an expanded proposition of this kind, '"^prefix^"' must be a proposition.\n"^
                "Why? Because this variable is part of a formula, and thus is expected\n"^
                "to be a proposition. Here is the content of '" ^prefix^"':\n"^
                "    "^(string_of_ast content), loc_affect)
          in eval_ast_formula (UnexpProp ((string_of_ast term), Some indices)) env
      (* Case 5. the variable was of the form '$v(1,2,3)' and was not declared
         and '$v' is not either declared, so we can safely guess that this var has not been declared. *)
      with Not_found -> raise_with_loc ast ("'" ^ name ^ "' has not been declared")
    end
  | Not Top    -> Bottom
  | Not Bottom -> Top
  | Not x      -> Not (eval_ast_formula x env)
  | And (Bottom, _) | And (_, Bottom) -> Bottom
  | And (Top,x)
  | And (x,Top) -> eval_ast_formula x env
  | And     (x,y) -> And (eval_ast_formula x env, eval_ast_formula y env)
  | Or (Top, _) | Or (_, Top) -> Top
  | Or (Bottom,x)
  | Or (x,Bottom) -> eval_ast_formula x env
  | Or      (x,y) -> Or  (eval_ast_formula x env, eval_ast_formula y env)
  | Xor     (x,y) -> Xor (eval_ast_formula x env, eval_ast_formula y env)
  | Implies (_,Top)
  | Implies (Bottom,_) -> Top
  | Implies (x,Bottom) -> eval_ast_formula (Not x) env
  | Implies (Top,x) -> eval_ast_formula x env
  | Implies (x,y) -> Implies (eval_ast_formula x env, eval_ast_formula y env)
  | Equiv   (x,y) -> Equiv (eval_ast_formula x env, eval_ast_formula y env)
  | Exact (x,y) -> begin (* !check_only simplifies by returning a dummy proposition *)
      match eval_ast x env, eval_ast y env with
      | Int x, Set (SSet s) -> if !check_only then Prop "dummy" else exact_str (PropSet.exact x s)
      | x',y' -> raise_type_error2 ast x x' y y' "'int' (left-hand)\nand a 'prop-set' (right-hand)"
    end
  | Atleast (x,y) -> begin
      match eval_ast x env, eval_ast y env with
      | Int x, Set (SSet s) -> if !check_only then Prop "dummy" else atleast_str (PropSet.atleast x s)
      | x',y' -> raise_type_error2 ast x x' y y' "'int' (left-hand)\nand a 'prop-set' (right-hand)"
    end
  | Atmost (x,y) ->begin
      match eval_ast x env, eval_ast y env with
      | Int x, Set (SSet s) -> if !check_only then Prop "dummy" else atmost_str (PropSet.atmost x s)
      | x',y' -> raise_type_error2 ast x x' y y' "'int' (left-hand)\nand a 'prop-set' (right-hand)"
    end
  (* What is returned by bigand or bigor when they do not
     generate anything? A direct solution would have been to
     return the 'neutral' element of the containing type, e.g.,
         ... and (bigand $i in []: p($i) end)
     would have to transform into
         ... and Top
     And we would have to know in what is the 'bigor/bigand'.
     Maybe we could bypass this problem: return Nothing when
     the bigand is empty; during the evaluation, Nothing will
     act like '... and Top' or '... or Bot'. *)
  | Bigand (vars,sets,when_optional,body) ->
    let when_cond = match when_optional with Some x -> x | None -> Bool true in
    begin check_nb_vars_same_as_nb_sets ast vars sets;
      match vars,sets with
      | [],[] | _,[] | [],_ -> failwith "shouln't happen: non-variable in big construct"
      | [Loc (Var (name,_),loc)],[set] -> (* we don't need the indices because bigand's vars are 'simple' *)
        let rec process_list_set (set_list:ast list) env =
          match set_list with
          | []   -> Top (*  what if bigand in a or? We give a warning (see below) *)
          | x::xs ->
            let env = (name,(x,loc))::env in
            match ast_to_bool when_cond env with
            | true when xs != [] -> And (eval_ast_formula body env, process_list_set xs env)
            | true  -> eval_ast_formula body env
            | false -> process_list_set xs env
        in
        let list_ast_set = set_to_ast_list set env in
        if (List.length list_ast_set) == 0 then
          warning set ("using 'bigand' on an empty set is not recommanded\n"^
            "as it returns a 'Top' formula which can give unexpected results");
          process_list_set list_ast_set env
      | x::xs,y::ys ->
        eval_ast_formula (Bigand ([x],[y],None,(Bigand (xs,ys,when_optional,body)))) env
    end
  | Bigor (vars,sets,when_optional,body) ->
    let when_cond = match when_optional with Some x -> x | None -> Bool true
    in
    begin check_nb_vars_same_as_nb_sets ast vars sets;
      match vars,sets with
      | [],[] | _,[] | [],_ -> failwith "shouln't happen: non-variable in big construct"
      | [Loc (Var (name,_),loc)],[set] ->
          let rec process_list_set (set_list:ast list) env =
            match set_list with
            | []    -> Bottom
            | x::xs ->
              let env = (name,(x,loc))::env in
              match ast_to_bool when_cond env with
              | true when xs != [] -> Or (eval_ast_formula body env, process_list_set xs env)
              | true  -> eval_ast_formula body env
              | false -> process_list_set xs env
          in
            let list_ast_set = set_to_ast_list set env in
          if (List.length list_ast_set) == 0 then
            warning set ("using 'bigor' on an empty set is not recommanded\n"^
              "as it returns a 'Bot' formula which can give unexpected results.");
            process_list_set list_ast_set env
      | x::xs,y::ys ->
        eval_ast_formula (Bigor ([x],[y],None,(Bigor (xs,ys,when_optional,body)))) env
    end
  | If (c,y,z) ->
    let test = match eval_ast c env with Bool c -> c | c' -> raise_type_error ast c c' "boolean"
    in if test then eval_ast_formula y env else eval_ast_formula z env
  | Let (Loc (Var (p,i),loc),content,formula) ->
    let name = (expand_var_name (p,i) env) and desc = (eval_ast content env,loc)
    in eval_ast_formula formula ((name,desc)::env)
  | Paren x -> eval_ast_formula x env
  | e -> raise_with_loc ast ("this expression is not a formula: " ^ string_of_ast e)

and exact_str lst =
  let rec go = function
    | [],[]       -> Top
    | t::ts,[]    -> And (And (Prop t, Top), go (ts,[]))
    | [],f::fs    -> And (And (Top, Not (Prop f)), go ([],fs))
    | t::ts,f::fs -> And (And (Prop t, Not (Prop f)), go (ts,fs))
  in
  match lst with
  | []    -> Bottom
  | x::xs -> Or (go x, exact_str xs)

and atleast_str lst =
  List.fold_left (fun acc str -> Or (acc, formula_of_string_list str)) Bottom lst

and atmost_str lst =
  List.fold_left (fun acc str ->
      Or (acc, List.fold_left (fun acc' str' ->
          And (acc', Not (Prop str'))) Top str)) Bottom lst

and formula_of_string_list =
  List.fold_left (fun acc str -> And (acc, Prop str)) Top

and and_of_term_list =
  List.fold_left (fun acc t -> And (acc, t)) Top

(* [expand_prop] will expand a proposition containing a set as index, e.g.,
   time([1,2],[a,b]) will become [time(1,a),time(1,b)...time(b,2)]. This is useful when 
   generating sets. *)
and expand_prop_with_set name ind env =
  let rec has_set ind = match ind with
    | []         -> false
    | (Set x)::_ -> true
    | _::next    -> has_set next
  in
  let ind = match ind with
    | None -> [UnexpProp (name,None)]
    | Some ind -> expand_prop_with_set' [UnexpProp (name,None)] ind env
  in
  let eval_unexpprop acc cur = match cur with 
    | UnexpProp (p,i) -> (expand_var_name (p,i) env)::acc | _->failwith "shouldnt happen"
  in let props_evaluated = List.fold_left eval_unexpprop [] ind in
  if has_set ind then Prop (List.nth props_evaluated 0)
  else Set (SSet (PropSet.of_list props_evaluated))

and expand_prop_with_set' proplist ind env = 
  match ind with
  | [] -> proplist
  | i::next -> 
    match eval_ast i env with
    | Set s -> let new_proplist = (expand_proplist proplist (set_to_ast_list (Set s) env)) in
        expand_prop_with_set' new_proplist next env
    | x -> expand_prop_with_set' (expand_proplist proplist [x]) next env
and expand_proplist proplist ind = match proplist with
  | [] -> []
  | x::xs -> (expand_prop x ind) @ (expand_proplist xs ind)
and expand_prop prop ind = match prop with
  | UnexpProp (name, None) -> List.fold_left (fun acc i -> (UnexpProp (name,Some ([i])))::acc) [] ind
  | UnexpProp (name, Some cur) -> List.fold_left (fun acc i -> (UnexpProp (name,Some (cur @ [i])))::acc) [] ind
  | x -> failwith ("[shouldnt happen] proplist contains smth that is not UnexpProp: "^string_of_ast_type x)
and expand_var_name (prefix,indices:string * ast list option) (env:env) =
  match (prefix,indices) with
  | (x,None)   -> x
  | (x,Some y) ->
    x ^ "("
    ^ (string_of_ast_list ", " (List.map (fun e -> eval_ast e env) y))
    ^ ")"

(* [set_to_ast_list] evaluates one element  of the list of things after
   the 'in' of bigand/bigor. 
   If this element is a set, it turns this Set (.) into a list of Int,
   Float or Prop.
   
   WARNING: this function reverses the order of the elements of the set;
   we could use fold_right in order to keep the original order, but 
   it would mean that it is not tail recursion anymore (= uses much more heap) 
   
   If [!check_only] is true, then the lists *)
and set_to_ast_list (ast:ast) env : ast list =
  let lst = match ast_whithout_loc (eval_ast ast env) with
  | Set (EmptySet)-> []
  | Set (ISet a) -> List.fold_left (fun acc v -> (Int v)::acc)   [] (IntSet.elements a)
  | Set (FSet a) -> List.fold_left (fun acc v -> (Float v)::acc) [] (FloatSet.elements a)
  | Set (SSet a) -> List.fold_left (fun acc v -> (Prop v)::acc)  [] (PropSet.elements a)
  | ast' -> raise_with_loc ast (
      "after 'in', only sets are allowed, but got '"^(string_of_ast_type ast')^"':\n"^
      "    "^(string_of_ast ast')^"\n"^
      "This element has been expanded to\n"^
      "    "^(string_of_ast ast')^"")
  in match !check_only, lst with (* useful when you only want to check types *)
          | false,      _      -> lst
          | true,       []     -> []
          | true,        x::xs -> [x]

  (* [ast_to_bool] evaluates the 'when' condition when returns 'true' or 'false'
     depending on the result. 
     This function is used in Bigand and Bigor statements. *)
  and ast_to_bool (ast:ast) env : bool = 
    match eval_ast ast env with 
    | Bool b -> b 
    | ast' -> raise_with_loc ast (
      "'when' expects a 'bool' but got '"^(string_of_ast_type ast')^"':\n"^
      "    "^(string_of_ast ast')^"\n"^
      "This element has been expanded to\n"^
      "    "^(string_of_ast ast')^"")