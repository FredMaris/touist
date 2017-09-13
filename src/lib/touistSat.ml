(** Processes the CNF-compliant version of the AST given by {!TouistCnf.ast_to_cnf}
    to create Minisat-compatible clauses with [minisat_clauses_of_cnf] and solve
    them with [solve_clauses].
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
open Minisat

(** [minisat_clauses_of_cnf ast] takes a CNF [ast] and outputs
    - a list of lists of Minisat litterals,
    - a mapping table (Minisat litterals -> name of the proposition)
*)
let minisat_clauses_of_cnf ast =
  let num_lit = ref 1 in
  let fresh_lit () = let lit = !num_lit in (incr num_lit; Minisat.Lit.make lit)
  in
  let clauses,lit_to_str,_ = TouistCnf.clauses_of_cnf Minisat.Lit.neg fresh_lit ast
  in clauses,lit_to_str

(** [clauses_to_solver] takes a list of clauses (clause = list of literals)
    and generates an intance of minisat solver.
    If, at any moment during the adding of the clauses, the formula becomes
    unsat, [clauses_to_solver] will return None. If we continued to add the
    other clauses, they would be discarded (not added) by minisat anyway. *)
let clauses_to_solver ?(verbose=false) (clauses:Lit.t list list) : Minisat.t option =
  let solver = Minisat.create () in
  if verbose then set_verbose solver 10;
  let rec add_clauses solver (l:Lit.t list list) : Minisat.t option =
    match l with
    | [] -> Some solver (* -> the formula did not become unsat while adding *)
    | cur::next -> let a = Array.of_list cur in
      if Minisat.Raw.add_clause_a solver a then add_clauses solver next else None
  in add_clauses solver clauses

(** for printing the Minisat.value type *)
let string_of_value = function
  | V_true -> "1"
  | V_false -> "0"
  | _ -> "?"

(** A container for remembering a model *)
module Model =
struct
  type t = (Minisat.Lit.t * Minisat.value) list
  let compare l1 l2 = Pervasives.compare l1 l2
  (* [dump] gives a string under the form (0,1)(1,2)(1,3)(0,4)... *)
  let dump l = List.fold_left (fun acc x -> match x with l,v -> ("("^(string_of_value v) ^ "," ^ (Lit.to_string l) ^ ")" ^ acc)) "" l
  (* [pprint] gives a string under the form
     1 prop(1,2,9)
     O prop(1,4,2)... *)
  let pprint ?(sep="\n") table model = List.fold_left 
      (fun acc (n,v) -> let str = (string_of_value v)^" "^(Hashtbl.find table n)
        in match acc with "" -> str | _ -> str ^ sep ^ acc)
      "" model
end

(** A set that contains all the models already found. *)
module ModelSet = struct
  include Set.Make(Model)
  let dump models = fold (fun m acc -> (Model.dump m) ^ "\n" ^ acc) models ""
  let pprint table models = fold (fun m acc -> (Model.pprint table m) ^ "=====\n" ^ acc) models ""
end

(** [get_model] retrieves the valuations from the current state of the solver
    and put them into a Model.t.
    [discard] must return true if the literal that is mapped to the given
    proposition name shouldn't be in the model. *)
let get_model solver (table:(Lit.t,string) Hashtbl.t) (discard:string->bool): Model.t =
  Hashtbl.fold (fun lit name acc ->
      if not (discard name) then (lit,Minisat.value solver lit)::acc else acc)
    table []

(* [string_of_clause] dumps the clause in its literal-number form:
   e.g., 1 -5 3 9 -2 -7 *)
let string_of_clause (clause:Lit.t list) : string =
  List.fold_left (fun acc lit -> (Lit.to_string lit) ^" "^ acc) "" clause
let string_of_clauses = List.fold_left (fun acc v -> (if acc="" then "" else acc^"\n")^(string_of_clause v)) ""
let print_clauses cls = Printf.fprintf stderr "%s" (string_of_clauses cls)

(* 1. Prevent current model from reappearing
   =========================================
   We must prevent the current model to reappear in future models;
   to do so, we add a clause that take the negation of the valuations
   E.g: with the model a=1, b=0 we must add the clause -a or b.
   [counter_clause] will produce a list of literals that corresponds
   to this clause. [counter_current_model] then adds the clause to the problem.
   IMPORTANT: When adding the counter-clause, the problem can become unsat.
   [counter_current_model] returns false if the added clause makes the
   formula unsat right away. *)

(* 2. Avoid duplicates caused by fake literals (of the form '&6')
   ==============================================================
   Our issue here: the models contain fake '&12' literals. We don't
   want to see these fake literals in our models; we also want to
   remove the duplicate models linked to these fake literals.
   To avoid those duplicates, we store the models (without the fake
   literals) in a set.

   To use this function, you need a ModelSet ref already initialized, e.g. with
    let models = ref ModelSet.empty *)

(* 3. Fetch the models
   ===================
   Basically, we
    (1) compute a model with Minisat.solve
    (2) check if we already saw this model (duplicates because of &23 literals)
    (3) prevent the same model from reappearing in adding the clause where all
        lits are the negation of the valuation in the model
    (4) go on with (1)
*)

(** [solve_clauses] finds the models for the given clauses.
    [print model N ] is a function that will print a model as soon as it is
      found. [N] is the number of the model, it begins at 1.
      It can be useful to print the models as they appear because finding all
      models (if [limit] is large) can be extremely long.
      Example: [~print:(TouistSat.Model.pprint table model)]
    [verbose] allows to turn on the verbose mode of minisat; apparently, this
      minisat feature doesn't seem to be working and doesn't display any time
      information.
    [continue model nth] is a function called after every model that has been
      found. [model] contains the found model and [N] says that this model was
      the nth model found. This function tells [solve_clauses] to go on searching
      models or not.
  *)
let solve_clauses
    ?(verbose=false)
    ?(print: Model.t -> int -> unit = fun m i ->())
    ?(continue: Model.t -> int -> bool = fun _ _ -> true)
    (clauses,table : Lit.t list list * (Lit.t,string) Hashtbl.t)
  : (ModelSet.t ref) =
  let counter_current_model solver (table:(Lit.t,string) Hashtbl.t) : bool =
    let counter_clause (l:Lit.t) _ acc = match Minisat.value solver l with
      | V_true -> (Minisat.Lit.neg l)::acc | V_false -> l::acc | _ -> acc
    in let counter_clause = Hashtbl.fold counter_clause table []
    in Minisat.Raw.add_clause_a solver (Array.of_list counter_clause)
  in (* already_unsat means that during the adding of clauses, the formula
        was found unsat. So we don't even need to solve it. *)
  let models = ref ModelSet.empty in
  match clauses_to_solver ~verbose clauses with
  | None -> models
  | Some solver ->
    (* searching for duplicate is slow on ModelSet. For checking a model hasn't
        appeared already, I use a way faster Hashtbl, ass it won't check on every
        single literal but compute a hash of the model) *)
    let models_hash = (Hashtbl.create 100) in
    let rec solve_loop i = (* i is the model counter *)
      if not (Minisat.Raw.simplify solver)
      || not (Minisat.Raw.solve solver [||])
      then models
      else
        let model = get_model solver table TouistCnf.is_dummy (* is_dummy removes &1 lits *)
        and has_next_model = counter_current_model solver table in
        let is_duplicate = Hashtbl.mem models_hash model in
        match is_duplicate,has_next_model with
        | true,false -> models (* is duplicate and no next model *)
        | true,true  -> solve_loop i (* is duplicate but has next *)
        | false,true ->  (* both not duplicate and has next *)
          models := ModelSet.add model !models; print model i;
          Hashtbl.add models_hash model ();
          if continue model i then solve_loop (i+1) else models
        | false, false -> (* is not duplicate and no next model *)
          models := ModelSet.add model !models; print model i;
          models
    in solve_loop 1

(** [print_solve] outputs the result of the solver. But it is much more
    recommanded to use the parameter [solve_clauses ~print_model:print...] in
    order to output the models as soon as they are found; if looking for a
    large number of models, [print_solve] will have to wait [solve_clauses]
    is done.

    [output] is the [out_channel] you want to solutions to be written
    into.
    [show_hidden] indicates that the hidden literals introduced during
    [ast_to_cnf].

    CNF conversion should be shown. *)
let print_solve ?(show_hidden=false) output (solver:Minisat.t) (table:(string, Minisat.Lit.t) Hashtbl.t) =
  let string_of_value solver (lit:Minisat.Lit.t) = match Minisat.value solver lit with
    | V_true -> "1" | V_false -> "0" | V_undef -> "?"
  in let print_value_and_name name lit = if show_hidden || name.[0] != '&'
       then Printf.fprintf output "%s %s\n" (string_of_value solver lit) name
  in Hashtbl.iter print_value_and_name table