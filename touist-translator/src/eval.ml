(*
 * eval.ml: semantic analysis of the abstract syntaxic tree produced by the parser.
 *          [eval] is the main function.
 *
 * Project TouIST, 2015. Easily formalize and solve real-world sized problems
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

exception Error of string
exception ErrorWithLoc of string * loc

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

(* [raise_type_error] raises the errors that come from one-parameter functions.
   operator is the non-expanded (expand = eval_ast) operator.
   Example: in 'To_int x', 'operand' is the non-expanded parameter 'x',
   'expanded' is the expanded parameter 'x'.
   Expanded means that eval_ast has been applied to x.
   [expected_types] contain a string that explain what is expected, e.g.,
   'an integer or a float'. *)
let raise_type_error operator operand expanded (expected_types:string) =
  match operand with
  | Var (_,_,loc) -> raise (ErrorWithLoc (
      "'"^(string_of_ast_type operator)^"' expects "^expected_types^".\n"^
      "The content of the variable '"^(string_of_ast operand)^"' has type '"^(string_of_ast_type expanded)^"':\n"^
      "    "^(string_of_ast expanded)^"", loc))
  | _ -> raise (Error (
      "'"^(string_of_ast_type operator)^"' expects "^expected_types^".\n"^
      "The operand:\n"^
      "    "^(string_of_ast operand)^"\n"^
      "has been expanded to something of type '"^(string_of_ast_type expanded)^"':\n"^
      "    "^(string_of_ast expanded)^""))

(* Same as above but for functions of two parameters. Example: with And (x,y),
   operator is And (x,y),
   op1 and op2 are the non-expanded parameters x and y,
   exp1 and exp2 are the expanded parameters x and y. *)
let raise_type_error2 operator op1 exp1 op2 exp2 (expected_types:string) =
  let var,content,loc,other,other_expanded = match op1,op2 with
    | Var (_,_,loc),_ -> op1,exp1,loc,op2,exp2
    | _,Var (_,_,loc) -> op2,exp2,loc,op1,exp1
    | _,_ -> raise (Error (
        "incorrect types with operator '"^(string_of_ast_type operator)^"', which expects "^expected_types^".\n"^
        "In statement:\n"^
        "    "^(string_of_ast operator)^"\n"^
        "Left-hand operand has type '"^(string_of_ast_type op1)^"':\n"^
        "    "^(string_of_ast exp1)^"\n"^
        "Right-hand operand has type '"^(string_of_ast_type exp2)^"':\n"^
        "    "^(string_of_ast exp2)^""^
        ""))
  in raise (ErrorWithLoc (
      "incorrect types with '"^(string_of_ast_type operator)^"', which expects "^expected_types ^".\n"^
      "The content of the variable '"^(string_of_ast var)^"' has type "^(string_of_ast_type content)^":\n"^
      "    "^(string_of_ast content)^"\n"^
      "The other operand is of type '"^(string_of_ast_type other_expanded)^"':\n"^
      "    "^(string_of_ast other_expanded)^"", loc))

(* [raise_set_decl] is the same as [raise_type_error2] but between one element
   and the set this element is supposed to be added to. *)
let raise_set_decl ast elmt elmt_expanded set set_expanded (expected_types:string) =
  match elmt with
  | Var (_,_,loc) -> raise (ErrorWithLoc (
      "Ill-formed set declaration. It expects "^expected_types^".\n"^
      "The content of the variable '"^(string_of_ast elmt)^"' has type '"^(string_of_ast_type elmt_expanded)^"':\n"^
      "    "^(string_of_ast elmt_expanded)^"\n"^
      "Up to now, the set declaration\n"^
      "    "^(string_of_ast set)^"\n"^
      "has been expanded to:\n"^
      "    "^(string_of_ast set_expanded)^"", loc))
  | _ -> raise (Error (
      "Ill-formed set declaration. It expects "^expected_types^".\n"^
      "One of the elements is of type '"^(string_of_ast_type elmt_expanded)^"':\n"^
      "    "^(string_of_ast elmt)^"\n"^
      "This element has been expanded to\n"^
      "    "^(string_of_ast elmt_expanded)^"\n"^
      "Up to now, the set declaration\n"^
      "    "^(string_of_ast set)^"\n"^
      "has been expanded to:\n"^
      "    "^(string_of_ast set_expanded)^""))


let check_nb_vars_and_sets (ast:ast) (vars: ast list) (sets: ast list) : unit =
  let fist_last_loc_of (varlist:ast list) : loc =
    match (List.nth varlist 0), List.nth varlist ((List.length varlist)-1) with
    | Var (_,_,(startpos,_)), Var (_,_,(_,endpos)) -> startpos,endpos
    | _,_ -> failwith "[shouldn't happen] non-variable in big construct"
  in
  match (List.length vars) == (List.length sets) with
  | true -> ()
  | false -> let vars_loc = fist_last_loc_of vars
    (* We only know the locations of the variables. To help the user, we give
       him the position of the list of variables. *)
    in raise (ErrorWithLoc (
        "Ill-formed '"^(string_of_ast_type ast)^"'. The number of variables and sets must be the same.\n"^
        "You defined "^(string_of_int (List.length vars))^" variables:\n"^
        "    "^(string_of_ast_list "," vars)^"\n"^
        "but you gave "^(string_of_int (List.length sets))^" sets:\n"^
        "    "^(string_of_ast_list "," sets)^"", vars_loc))
  

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

let extenv = Hashtbl.create 10

let rec eval ast =
  eval_touist_code ast []

and eval_touist_code ast (env:env) =
  let rec loop = function
    | []    -> raise (Error ("no formulas"))
    | [x]   -> x
    | x::xs -> And (x, loop xs)
  in
  match ast with
  | Touist_code (formulas, None) -> eval_ast_formula (loop formulas) env
  | Touist_code (formulas, Some decl) ->
    List.iter (fun x -> eval_affect x env) decl;
    eval_ast_formula (loop formulas) env
  | e -> raise (Error ("this does not seem to be a touist code structure: " ^ string_of_ast e))


and eval_affect ast env =
  match ast with
  | Affect (Var (p,i,loc),y) ->
    Hashtbl.replace extenv (expand_var_name (p,i) env) (eval_ast y env, loc)
  | e -> raise (Error ("this does not seem to be an affectation: " ^ string_of_ast e))

(* [eval_ast] evaluates (= expands) numerical, boolean and set expresions that
   are not directly in formulas. For example, in 'when $a!=a' or 'if 3>4',
   the boolean values must be computed: eval_ast will do exactly that.*)
and eval_ast (ast:ast) (env:env) =
  match ast with
  | Int x   -> Int x
  | Float x -> Float x
  | Bool x  -> Bool x
  | Var (p,i,loc) -> (* p,i = prefix, indices *)
    let name = expand_var_name (p,i) env in
    begin
      try let (content,loc) = List.assoc name env in content
      with Not_found ->
      try let (content,_) = Hashtbl.find extenv name in content
      with Not_found -> raise (ErrorWithLoc (
          "variable '" ^ name ^"' does not seem to be known. Either you forgot\n"^
          "to declare it globally or it has been previously declared locally\n"^
          "(with bigand, bigor or let) and you are out of its scope.", loc))
    end
  | Set x -> Set x
  | Set_decl x -> eval_set_decl ast env
  | Neg x -> (match eval_ast x env with
      | Int x'   -> Int   (- x')
      | Float x' -> Float (-. x')
      | x' -> raise_type_error ast x x' "float or integer")
  | Add (x,y) -> (match eval_ast x env, eval_ast y env with
      | Int x, Int y -> Int (x + y)
      | Float x, Float y -> Float (x +. y)
      | x',y' -> raise_type_error2 ast x y x' y' "float or integer")
  | Sub (x,y) -> (match eval_ast x env, eval_ast y env with
      | Int x, Int y -> Int (x - y)
      | Float x, Float y -> Float (x -. y)
      | x',y' -> raise_type_error2 ast x y x' y' "float or integer")
  | Mul (x,y) -> (match eval_ast x env, eval_ast y env with
      | Int x, Int y -> Int (x * y)
      | Float x, Float y -> Float (x *. y)
      | x',y' -> raise_type_error2 ast x y x' y' "a float or integer")
  | Div (x,y) -> (match eval_ast x env, eval_ast y env with
      | Int x, Int y -> Int (x / y)
      | Float x, Float y -> Float (x /. y)
      | x',y' -> raise_type_error2 ast x y x' y' "a float or integer")
  | Mod (x,y) -> (match eval_ast x env, eval_ast y env with
      | Int x, Int y -> Int (x mod y)
      | x',y' -> raise_type_error2 ast x y x' y' "a float or integer")
  | Sqrt x -> (match eval_ast x env with
      | Float x -> Float (sqrt x)
      | x' -> raise_type_error ast x x' "a float")
  | To_int x -> (match eval_ast x env with
      | Float x -> Int (int_of_float x)
      | Int x   -> Int x
      | x' -> raise_type_error ast x x' "a float or integer")
  | To_float x -> (match eval_ast x env with
      | Int x   -> Float (float_of_int x)
      | Float x -> Float x
      | x' -> raise_type_error ast x x' "a float or integer")
  | Abs x -> (match eval_ast x env with
      | Int x   -> Int (abs x)
      | Float x -> Float (abs_float x)
      | x' -> raise_type_error ast x x' "a float or integer")
  | Not x -> (match eval_ast x env with
      | Bool x -> Bool (not x)
      | x' -> raise_type_error ast x x' "a boolean")
  | And (x,y) -> (match eval_ast x env, eval_ast y env with
      | Bool x,Bool y -> Bool (x && y)
      | x',y' -> raise_type_error2 ast x y x' y' "a boolean")
  | Or (x,y) -> (match eval_ast x env, eval_ast y env with
      | Bool x,Bool y -> Bool (x || y)
      | x',y' -> raise_type_error2 ast x y x' y' "a boolean")
  | Xor (x,y) -> (match eval_ast x env, eval_ast y env with
      | Bool x,Bool y -> Bool ((x || y) && (not (x && y)))
      | x',y' -> raise_type_error2 ast x y x' y' "a boolean")
  | Implies (x,y) -> (match eval_ast x env, eval_ast y env with
      | Bool x,Bool y -> Bool (not x || y)
      | x',y' -> raise_type_error2 ast x y x' y' "a boolean")
  | Equiv (x,y) -> (match eval_ast x env, eval_ast y env with
      | Bool x,Bool y -> Bool ((not x || y) && (not x || y))
      | x',y' -> raise_type_error2 ast x y x' y' "a boolean")
  | If (x,y,z) ->
    let test =
      match eval_ast x env with
      | Bool true  -> true
      | Bool false -> false
      | x' -> raise_type_error ast x x' "a boolean"
    in
    if test then eval_ast y env else eval_ast z env
  | Union (x,y) -> begin
      let x',y' = eval_ast x env, eval_ast y env in
      match process_empty x' y', process_empty y' x' with
      | Set (ISet a), Set (ISet b) -> Set (ISet (IntSet.union a b))
      | Set (FSet a), Set (FSet b) -> Set (FSet (FloatSet.union a b))
      | Set (SSet a), Set (SSet b) -> Set (SSet (PropSet.union a b))
      | _,_ -> raise_type_error2 ast x y x' y' "a set of float, int or prop"
    end
  | Inter (x,y) -> begin
      let x',y' = eval_ast x env, eval_ast y env in
      match process_empty x' y', process_empty y' x' with
      | Set (ISet a), Set (ISet b) -> Set (ISet (IntSet.inter a b))
      | Set (FSet a), Set (FSet b) -> Set (FSet (FloatSet.inter a b))
      | Set (SSet a), Set (SSet b) -> Set (SSet (PropSet.inter a b))
      | _,_ -> raise_type_error2 ast x y x' y' "a set of float, int or prop"
    end
  | Diff (x,y) -> begin
      let x',y' = eval_ast x env, eval_ast y env in
      match process_empty x' y', process_empty y' x' with
      | Set (ISet a), Set (ISet b) -> Set (ISet (IntSet.diff a b))
      | Set (FSet a), Set (FSet b) -> Set (FSet (FloatSet.diff a b))
      | Set (SSet a), Set (SSet b) -> Set (SSet (PropSet.diff a b))
      | _,_ -> raise_type_error2 ast x y x' y' "a set of float, int or prop"
    end
  | Range (x,y) ->
    (* Return the list of integers between min and max with an increment of step *)
    let irange min max step =
      let rec loop acc = function i when i=max+1 -> acc | i -> loop (i::acc) (i+step)
      in loop [] min |> List.rev
    and frange min max step =
      let rec loop acc = function i when i=max+.1. -> acc | i -> loop (i::acc) (i+.step)
      in loop [] min |> List.rev
    in begin
      match eval_ast x env, eval_ast y env with
      | Int x, Int y     -> Set (ISet (IntSet.of_list (irange x y 1)))
      | Float x, Float y -> Set (FSet (FloatSet.of_list (frange x y 1.)))
      | x',y' -> raise_type_error2 ast x y x' y' "two integers or two floats"
    end
  | Empty x -> begin
      match eval_ast x env with
      | Set (EmptySet)    -> Bool true
      | Set (ISet x) -> Bool (IntSet.is_empty x)
      | Set (FSet x) -> Bool (FloatSet.is_empty x)
      | Set (SSet x) -> Bool (PropSet.is_empty x)
      | x' -> raise_type_error ast x x' "a set of float, int or prop"
    end
  | Card x -> begin
      match eval_ast x env with
      | Set (EmptySet)    -> Int 0
      | Set (ISet x) -> Int (IntSet.cardinal x)
      | Set (FSet x) -> Int (FloatSet.cardinal x)
      | Set (SSet x) -> Int (PropSet.cardinal x)
      | x' -> raise_type_error ast x x' "a set of float, int or prop"
    end
  | Subset (x,y) -> begin
      let x',y' = eval_ast x env, eval_ast y env in
      match process_empty x' y', process_empty y' x' with
      | Set (ISet a), Set (ISet b) -> Bool (IntSet.subset a b)
      | Set (FSet a), Set (FSet b) -> Bool (FloatSet.subset a b)
      | Set (SSet a), Set (SSet b) -> Bool (PropSet.subset a b)
      | _,_ -> raise_type_error2 ast x y x' y' "a set of float, int or prop"
    end
  | In (x,y) ->
    begin match eval_ast x env, eval_ast y env with
      | _, Set (EmptySet) -> Bool false (* nothing can be in an empty set!*)
      | Int x, Set (ISet y) -> Bool (IntSet.mem x y)
      | Float x', Set (FSet y') -> Bool (FloatSet.mem x' y')
      | Prop x', Set (SSet y') -> Bool (PropSet.mem x' y')
      | x',y' -> raise_type_error2 ast x x' y y' "an int, float or prop (left-hand) and a set (right-hand)"
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
      | x',y' -> raise_type_error2 ast x y x' y' "a float or int")
  | Lesser_or_equal (x,y) -> (match eval_ast x env, eval_ast y env with
      | Int x, Int y -> Bool (x <= y)
      | Float x, Float y -> Bool (x <= y)
      | x',y' -> raise_type_error2 ast x y x' y' "a float or int")
  | Greater_than     (x,y) -> (match eval_ast x env, eval_ast y env with
      | Int x, Int y -> Bool (x > y)
      | Float x, Float y -> Bool (x > y)
      | x',y' -> raise_type_error2 ast x y x' y' "a float or int")
  | Greater_or_equal (x,y) -> (match eval_ast x env, eval_ast y env with
      | Int x, Int y -> Bool (x >= y)
      | Float x, Float y -> Bool (x >= y)
      | x',y' -> raise_type_error2 ast x y x' y' "a float or int")
  | UnexpProp (p,i) -> Prop (expand_var_name (p,i) env)
  | Prop x -> Prop x
  | e -> raise (Error ("this expression cannot be expanded: " ^ string_of_ast e))

and eval_set_decl (set_decl:ast) (env:env) =
  let sets = (match set_decl with Set_decl sets -> sets | _ -> failwith "shoulnt happen: non-Set_decl in eval_set_decl") in
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
  match ast with
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
  | Var (p,i,loc) -> (* p,i = prefix,indices *)
    (* name = prefix + indices. 
       Example with $v(a,b,c):
       name is '$v(a,b,c)', prefix is '$v' and indices are '(a,b,c)' *)
    let name = expand_var_name (p,i) env in
    begin
      (* Case 1. Check if this variable name has been affected locally 
         (recursive-wise) in bigand, bigor or let. *)
      try let content,loc_affect = List.assoc name env in
        match content with
        | Int x' -> Int x'
        | Float x' -> Float x'
        | Prop x -> Prop x
        | _ -> raise (ErrorWithLoc (
            "'" ^ name ^ "' has been declared locally (in bigand, bigor or let)\n" ^
            "Locally declared variables must be scalar (float, int or term).\n" ^
            "Instead, the content of the variable has type '"^(string_of_ast_type content)^"':\n"^
            "    "^(string_of_ast content),loc_affect))
      with Not_found ->
      (* Case 2. Check if this variable name has been affected globally, i.e.,
         in the 'data' section *)
      try let (content,loc_affect) = Hashtbl.find extenv name in
        match content with
        | Int x' -> Int x'
        | Float x' -> Float x'
        | Prop x -> Prop x
        | _ -> raise (ErrorWithLoc (
            "the global variable '" ^ name ^ "' should be a scalar (number or term).\n" ^
            "Instead, the content of the variable has type '"^(string_of_ast_type content)^"':\n"^
            "    "^(string_of_ast content), loc_affect))
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
            | Int x -> Int x
            | Float x -> Float x
            | Prop x -> Prop x
            | wrong -> raise (ErrorWithLoc (
                "'" ^ name ^ "' has not been declared; maybe you wanted '"^prefix^"' to expand\n" ^
                "in order to produce an expanded version <"^prefix^"-content>("^(string_of_ast_list "," indices)^")." ^
                "But the content of the variable '"^prefix^"' has type '"^(string_of_ast_type wrong)^"':\n"^
                "    "^(string_of_ast wrong)^"\n'"^
                "which is not a term or a number, so it cannot be expanded as explained above.", loc_affect))
          in eval_ast_formula (UnexpProp ((string_of_ast term), Some indices)) env
      (* Case 5. the variable was of the form '$v(1,2,3)' and was not declared
         and '$v' is not either declared, so we can safely guess that this var has not been declared. *)
      with Not_found -> raise (ErrorWithLoc ("'" ^ name ^ "' has not been declared", loc))
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
  | Exact (x,y) -> begin
      match eval_ast x env, eval_ast y env with
      | Int x, Set (SSet s) -> exact_str (PropSet.exact x s)
      | x',y' -> raise_type_error2 ast x y x' y' "int (left-hand) and a set of prop (right-hand)"
    end
  | Atleast (x,y) -> begin
      match eval_ast x env, eval_ast y env with
      | Int x, Set (SSet s) -> atleast_str (PropSet.atleast x s)
      | x',y' -> raise_type_error2 ast x y x' y' "int (left-hand) and a set of prop (right-hand)"
    end
  | Atmost (x,y) ->begin
      match eval_ast x env, eval_ast y env with
      | Int x, Set (SSet s) -> atmost_str (PropSet.atmost x s)
      | x',y' -> raise_type_error2 ast x y x' y' "int (left-hand) and a set of prop (right-hand)"
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
  | Bigand (v,s,t,e) ->
    let test =
      match t with
      | Some x -> x
      | None   -> Bool true
    in
    begin check_nb_vars_and_sets ast v s;
      match v,s with
      | [],[] | _,[] | [],_ -> failwith "shouln't happen: non-variable in big construct"
      | [Var (p,i,loc)],[y] ->
        begin
          match eval_ast y env with
          | Set (EmptySet)  -> bigand_empty env (p,i,loc) [] test e
          | Set (ISet a) -> bigand_int   env (p,i,loc) (IntSet.elements a)    test e
          | Set (FSet a) -> bigand_float env (p,i,loc) (FloatSet.elements a)  test e
          | Set (SSet a) -> bigand_str   env (p,i,loc) (PropSet.elements a) test e
          | y' -> raise_type_error ast y y' "a comma-separated list of sets after 'in'"
        end
      | x::xs,y::ys ->
        eval_ast_formula (Bigand ([x],[y],None,(Bigand (xs,ys,t,e)))) env
    end
  | Bigor (v,s,t,e) ->
    let test =
      match t with
      | Some x -> x
      | None   -> Bool true
    in
    begin check_nb_vars_and_sets ast v s;
      match v,s with
      | [],[] | _,[] | [],_ -> failwith "shouln't happen: non-variable in big construct"
      | [Var (p,i,loc)],[y] -> begin
          match eval_ast y env with
          | Set (EmptySet)  -> bigor_empty env (p,i,loc) [] test e
          | Set (ISet a) -> bigor_int   env (p,i,loc) (IntSet.elements a)    test e
          | Set (FSet a) -> bigor_float env (p,i,loc) (FloatSet.elements a)  test e
          | Set (SSet a) -> bigor_str   env (p,i,loc) (PropSet.elements a) test e
          | y' -> raise_type_error ast y y' "a comma-separated list of sets after 'in'"
        end
      | x::xs,y::ys ->
        eval_ast_formula (Bigor ([x],[y],None,(Bigor (xs,ys,t,e)))) env
    end
  | If (c,y,z) ->
    let test = match eval_ast c env with Bool c -> c | c' -> raise_type_error ast c c' "boolean"
    in if test then eval_ast_formula y env else eval_ast_formula z env
  | Let (Var (p,i,loc),content,formula) ->
    let name = (expand_var_name (p,i) env) and desc = (eval_ast content env,loc)
    in eval_ast_formula formula ((name,desc)::env)
  | e -> raise (Error ("this expression is not a formula: " ^ string_of_ast e))


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

and bigand_empty env var values test ast = Top (* XXX what if bigand in a or?*)
and bigand_int env var values test ast =
  let ast' = If (test,ast,Top) and name,_,loc = var in 
  match values with
  | []    -> Top
  | [x]   -> eval_ast_formula ast' ((name, (Int x, loc))::env)
  | x::xs -> And (eval_ast_formula ast' ((name, (Int x,loc))::env) ,bigand_int env var xs test ast)
and bigand_float env var values test ast =
  let ast' = If (test,ast,Top) and name,_,loc = var in
  match values with
  | []    -> Top
  | [x]   -> eval_ast_formula ast' ((name, (Float x,loc))::env)
  | x::xs -> And (eval_ast_formula ast' ((name, (Float x,loc))::env) ,bigand_float env var xs test ast)
and bigand_str env var values test ast =
  let ast' = If (test,ast,Top) and name,_,loc = var in
  match values with
  | []    -> Top
  | [x]   -> eval_ast_formula ast' ((name, (Prop x,loc))::env)
  | x::xs ->
    And (eval_ast_formula ast' ((name, (Prop x,loc))::env), bigand_str env var xs test ast)
and bigor_empty env var values test ast = Bottom
and bigor_int env var values test ast =
  let ast' = If (test,ast,Bottom) and name,_,loc = var in
  match values with
  | []    -> Bottom
  | [x]   -> eval_ast_formula ast' ((name, (Int x,loc))::env)
  | x::xs -> Or (eval_ast_formula ast' ((name, (Int x,loc))::env), bigor_int env var xs test ast)
and bigor_float env (var:string * ast list option * loc) values test ast =
  let ast' = If (test,ast,Bottom) and name,_,loc = var in
  match values with
  | []    -> Bottom
  | [x]   -> eval_ast_formula ast' ((name, (Float x,loc))::env)
  | x::xs -> Or (eval_ast_formula ast' ((name, (Float x,loc))::env), bigor_float env var xs test ast)
and bigor_str env var values test ast =
  let ast' = If (test,ast,Bottom) and name,_,loc = var in
  match values with
  | []    -> Bottom
  | [x]   -> eval_ast_formula ast' ((name, (Prop x,loc))::env)
  | x::xs ->
    Or (eval_ast_formula ast' ((name, (Prop x,loc))::env), bigor_str env var xs test ast)

and expand_var_name (prefix,indices:string * ast list option) (env:env) =
  match (prefix,indices) with
  | (x,None)   -> x
  | (x,Some y) ->
    x ^ "("
    ^ (string_of_ast_list ", " (List.map (fun e -> eval_ast e env) y))
    ^ ")"
