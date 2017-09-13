(** Processes the "semantically correct" abstract syntax tree (ast) given by {!TouistEval.eval}
    to produce a CNF-compliant version of the abstract syntax tree.

    [ast_to_cnf] is the main function.

    {2 Vocabulary}

    {ul{- Literal:
      a possibly negated proposition; we denote them as a, b... and
      their type is homogenous to [Prop _] or [Not(Prop _)] or [Top] or [Bottom].
      Exples:
        - [ a        ]                        is a literal,
        - [ not b    ]                        is a literal.

    }{- Clause:
      a disjunction (= separated by "or") of possibly negated literals.
      Example of clause:
        - [ a or not b or c or d   ]          is a clause

    }{- Conjunction:
      literals separated by "and"; example:
        - [ a and b and not and not d    ]    is a conjunction

    }{- AST:
      abstract syntax tree; it is homogenous to TouistTypes.Ast.ast
      and is a recursive tree representing a formula, using Or, And, Implies...
      Example: the formula (1) has the abstract syntax tree (2):
        - [ (a or b) and not c    ]                  (1) natural language
        - [ And (Or (Prop x, Prop x),Not (Prop x))  ](2) abstract syntax tree

    }{- CNF:
      a Conjunctive Normal Form is an AST that has a special structure with
      is a conjunction of disjunctions of literals. For example:
        - [ (a or not b) and (not c and d)   ]    is a CNF form
        - [ (a and b) or not (c or d)        ]    is not a CNF form

    }}
*)

(* Project TouIST, 2015. Easily formalize and solve real-world sized problems
 * using propositional logic and linear theory of reals with a nice language and GUI.
 *
 * https://github.com/touist/touist
 *
 * Copyright Institut de Recherche en Informatique de Toulouse, France
 * This program and the accompanying materials are made available
 * under the terms of the GNU Lesser General Public License (LGPL)
 * version 2.1 which accompanies this distribution, and is available at
 * http://www.gnu.org/licenses/lgpl-2.1.html *)

open TouistTypes.Ast
open TouistPprint
open TouistErr

(* [is_clause] checks that the given AST is a clause. This function can only
   be called on an AST containing Or, And or Not. No Equiv or Implies! *)
let rec is_clause (ast: ast) : bool = match ast with
  | Top | Bottom | Prop _ | Not (Prop _) -> true
  | Or (x,y) -> is_clause x && is_clause y
  | And _ -> false
  | x -> false

(** [push_lit] allows to translate into CNF the non-CNF disjunction [d or cnf]
    ([d] is the literal we want to add, [cnf] is the existing CNF form).
    For example:
    {[
          d  or  ((a or not b) and (not c))            <- is not in CNF
    <=>   push_lit (d) ((a or not b) and not c)
    <=>   (d or a or b) and (d or not c)               <- is in CNF
    ]}
    This function is necessary because [d or cnf] (with [cnf] an arbitrary CNF
    form) is not a CNF form and must be modified. Conversely, the form
          [d  and  ((a or not b) and (not c))]
    doesn't need to be modified because it is already in CNF.  *)
let rec push_lit (lit:ast) (cnf:ast) : ast =
  let push_lit = push_lit in
  match cnf with
  | Top              -> Top
  | Bottom           -> lit
  | Prop x           -> Or (lit, Prop x) (* p,i = prefix, indices *)
  | Not (Prop x)     -> Or (lit, Not (Prop x))
  | And (x,y)        -> And (push_lit lit x, push_lit lit y)
  | Or (x,y)         -> Or (lit, Or (x,y))
  | ast -> failwith ("[shouldnt happen] this doesn't seem to be a formula: '" ^ (string_of_ast ~debug:true ast) ^ "'")



(** [fresh_dummy] generates a 'dummy' proposition named ["&i"] with [i] being a
    self-incrementing index.
    This function allows to speed up and simplify the translation of some
    forms of Or.
    NOTE: OCaml's functions can't have 0 param: we use the unit [()]. *)
let dummy_term_count = ref 0
let fresh_dummy () =
  incr dummy_term_count; Prop ("&" ^ (string_of_int !dummy_term_count))

(** [is_dummy name] tells (using the [name] of a litteral) is a 'dummy' literal
    that was introduced during cnf conversion; these literals are identified
    by their prefix '&'. *)
let is_dummy (name:string) : bool = (name).[0] = '&'

let debug = ref false (* The debug flag activated by --debug-cnf *)

(** [print_debug] is just printing debug info in [to_cnf] *)
let print_debug (prefix:string) depth (formulas:ast list) : unit =
  (* [indent] creates a string that contains N indentations *)
  let rec indent = function 0 -> "" | i -> (indent (i-1))^"\t"
  and string_of_asts = function
    | [] -> ""
    | cur::[] -> string_of_ast ~utf8:true cur
    | cur::next -> (string_of_ast ~utf8:true cur)^", "^(string_of_asts next)
  in print_endline ((indent depth) ^ (string_of_int depth) ^ " " ^ prefix
                    ^ (string_of_asts formulas))

(** [stop] is a type is used in [to_cnf] in order to stop it after a number of
   recursions. See (1) below *)
type stop = No | Yes of int

(** [ast_to_cnf] translates the syntaxic tree made of Or, And, Implies, Equiv...
    Or, And and Not; moreover, it can only be in a conjunction of formulas
    (see a reminder of their definition above).
    For example (instead of And, Or we use "and" and "or" and "not"):
    {v
        (a or not b or c) and (not a or b or d) and (d)
    v}
    The matching abstract syntax tree (ast) is
    {v
        And (Or a,(Cor (Not b),c)), (And (Or (Or (Not a),b),d), d)
    v}
 *)
let rec ast_to_cnf ?debug:(d=false) (ast:ast) : ast =
  debug := d;
  to_cnf 0 No ast

(** Actual logic of [ast_to_cnf]
    [depth] tells what is the current level of recursion and
    helps for debugging the translation to CNF.
    [stop] tells to_cnf if it should stop or continue the recursion.

    - (1) When transforming to CNF, we want to make sure that "outer" to_cnf
        transformations are made before inner ones. For example, in
        {v
            to_cnf (Not (to_cnf ((a and b) => c)))
        v}
        we want to limit the inner [to_cnf] expansion to let the possibily for
        the outer to_cnf to "simplify" with the Not as soon as possible.
        For inner [to_cnf], we simply use [to_cnf_once] to prevent the inner
        [to_cnf] from recursing more than once.
    - (2) All bottom and top must disappear for the CNF transformation; we use
        the standard transformation to remove them (a and not a, b or not b) *)
and to_cnf depth (stop:stop) (ast:ast) : ast =
  if !debug then print_debug "in:  " depth [ast];
  if (match stop with Yes 0 -> true | _ -> false) then ast else (* See (1) above*)
    let to_cnf_once = to_cnf (depth+1) (match stop with Yes i->Yes (i-1) | No->Yes 1) in
    let to_cnf = to_cnf (depth+1) (match stop with Yes i->Yes (i-1) | No->No) in
    let cnf = begin match ast with
    | Top when depth=0 -> let t = fresh_dummy () in Or (t,Not t) (* See (2) above *)
    | Top -> Top
    | Bottom when depth=0 -> let t = fresh_dummy () in And (t,Not t) (* See (2) *)
    | Bottom -> Bottom
    | Prop x -> Prop x
    | And (x,y) -> let (x,y) = (to_cnf x, to_cnf y) in
      begin
        match x,y with
        | Top,x | x,Top     -> x
        | Bottom,_|_,Bottom -> Bottom
        | x,y               -> And (x,y)
      end
    | Not x ->
      begin
        match x with
        | Top        -> Bottom
        | Bottom     -> Top
        | Prop x     -> Not (Prop x)
        | Not x     -> to_cnf x
        | And (x,y) -> to_cnf (Or (Not x, Not y))           (* De Morgan *)
        | Or (x,y)  -> And (to_cnf (Not x), to_cnf (Not y)) (* De Morgan *)
        | _ -> to_cnf (Not (to_cnf_once x)) (* See (1) above*)
      end
    | Or (x,y) -> if !debug then print_debug "Or: " depth [x;y];
      let (x,y) = (to_cnf x, to_cnf y) in
      begin
        match x,y with
        | Bottom, z | z, Bottom   -> z
        | Top, _ | _, Top         -> Top
        | Prop x, z | z, Prop x   -> push_lit (Prop x) z
        | Not (Prop x),z | z,Not (Prop x) -> push_lit (Not (Prop x)) z
        | x,y when is_clause x && is_clause y -> Or (x, y)
        | x,y -> (* At this point, either x or y is a conjunction
                    => Tseytin transform (see explanations below) *)
          let (new1, new2) = (fresh_dummy (), fresh_dummy ()) in
          And (Or (new1, new2), And (push_lit (Not new1) x,
                                        push_lit (Not new2) y))
      end
        (* Note on [Or] and the Tseytin transform:
           When translating [x or y] into CNF and that either x or y is a
           conjunction (= isn't a clause), we must avoid the 'natural' translation
           that should occur when translating (1) into (2): (2) would have an
           exponential number of clauses. Instead, we use arbitrary variables
           created by [genterm], denoted by &1, &2... and use the Tseytin
           transform (3) which yields a linear number of clauses.
                (x1 and y1)  or  (x2 and y2)                                (1)
                (x1 or x2) and (x1 or y2) and (y1 or x2) or (etc...)        (2)
                (&1 or &2) and (not &1 or x1) and (not &1 or y1)            (3)
                          and (not &2 or x2) and (not &2 or y2)
        *)
    | Implies (x,y) -> to_cnf (Or (Not x, y))
    | Equiv (x,y) -> to_cnf (And (Implies (x,y), Implies (y,x)))
    | Xor (x,y) -> to_cnf (And (Or (x,y), Or (Not x, Not y)))
    | _ -> failwith ("[shouldnt happen] this doesn't seem to be a formula: '"
      ^ (string_of_ast ~debug:true ast) ^ "'")
    end
    in
    if !debug then print_debug "out: " depth [cnf];
    (* Last important thing: make sure no more Bot/Top are in the formula. *)
    if depth=0 && TouistEval.has_top_or_bot cnf then to_cnf cnf else cnf


(** The following functions are for displaying dimacs/qdimacs format.
    Example for the formula
    {v
         rain=>wet and rain and not wet
    v}
    we get the dimacs file:
    {v
        c CNF format file                 <-- by hand
        p cnf 2 3                         <-- by hand (nb_lits, nb_clauses)
        -2 1 0                            <-- [print_clauses_to_dimacs]
        -2 2 0
        -2 -1 0
        c wet 1                           <-- (optionnal) [print_table]
        c rain 2
    v}
*)

(** [clauses_of_cnf] translates the cnf ast (Not, And, Or, Prop; no Bot/Top)
    into a CNF formula that takes the form of a list of lists of litterals
    (conjunctions of disjunctions of possibly negated proprositions).
    [neg lit] returns the negation of the litteral (not)
    [fresh ()] returns a newly generated litteral
    Returns:
    - the list of lists of litterals
    - the table literal-to-name
    Note that the total number of literals is exactly equal to the table size;
    this size includes the special propositions beginning with '&' (e.g., '&4'). *)
let clauses_of_cnf (neg:'a->'a) (fresh:unit->'a) (ast:ast)
  : 'a list list * ('a, string) Hashtbl.t * (string, 'a) Hashtbl.t =
  (* num = a number that will serve to identify a literal
      lit = a literal that has a number inside it to identify it *)
  let str_to_lit = Hashtbl.create 500 in
  let lit_to_str = Hashtbl.create 500 in (* this duplicate is for the return value *)
  let rec process_cnf ast : 'a list list = match ast with
    | And  (x,y) -> (process_cnf x) @ (process_cnf y)
    | x when is_clause x -> [process_clause x]
    | _ -> failwith ("CNF: was expecting a conjunction of clauses but got '" ^ (string_of_ast ~debug:true ast) ^ "'")
  and process_clause (ast:ast) : 'a list = match ast with
    | Prop str        -> (gen_lit str)::[]
    | Not (Prop str) -> (neg (gen_lit str))::[]
    | Or (x,y) -> process_clause x @ process_clause y
    | _ -> failwith ("CNF: was expecting a clause but got '" ^ (string_of_ast ~debug:true ast) ^ "'")
  and gen_lit (s:string) : 'a =
    try Hashtbl.find str_to_lit s
    with Not_found ->
      (let lit = fresh () in
       Hashtbl.add str_to_lit s lit;
       Hashtbl.add lit_to_str lit s;
       lit)
  in let clauses = process_cnf ast in clauses, lit_to_str, str_to_lit

(** [print_table] prints the correspondance table between literals (= numbers)
    and user-defined proposition names, e.g.,

        'p(1,2) 98'

    where 98 is the literal id number (given automatically) and 'p(1,2)' is the
    name of this proposition.

    NOTE: you can add a prefix to 'p(1,2) 98', e.g.
      [string_of_table ~prefix:"c " table]
    in order to have all lines beginning by 'c' (= comment) in order to comply to
    the DIMACS format. *)
let print_table (int_of_lit: 'a->int) (out:out_channel) ?(prefix="") (table:('a,string) Hashtbl.t) =
  let print_lit_and_name lit name = Printf.fprintf out "%s%s %d\n" prefix name (int_of_lit lit)
  in Hashtbl.iter print_lit_and_name table

(** [print_clauses_to_dimacs] prints one disjunction per line ended by 0:
    {v
       -2 1 0
       -2 2 0
    v}
    IMPORTANT: prints ONLY the clauses. You must print the dimacs/qdimacs
    header yourself, e.g.:
    {v
       p cnf <nb_lits> <nb_clauses>      with <nb_lits> = Hashtbl.length table
                                              <nb_clauses> = List.length clauses
    v} *)
let print_clauses_to_dimacs (out:out_channel) (str_of_lit: 'a->string) (clauses:'a list list) : unit =
  let rec string_of_clause (cl:'a list) = match cl with
    | [] -> "0"
    | cur::next -> (str_of_lit cur) ^" "^ (string_of_clause next)
  and print_listclause (cl:'a list list) = match cl with
    | [] -> ()
    | cur::next -> Printf.fprintf out "%s\n" (string_of_clause cur); print_listclause next
  in
  print_listclause clauses