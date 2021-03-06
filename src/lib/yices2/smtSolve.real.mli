(** {b Requires [yices2]} Process an evaluated AST in order to solve
    it with Yices2. *)

val ast_to_yices :
  Touist.Types.AstSet.elt -> Yices2.term * (string, Yices2.term) Hashtbl.t

val string_of_model :
  ?value_sep:string -> (string, Yices2.term) Hashtbl.t -> Yices2.model -> string
(** Turn a model into a string. *)

val solve : string -> Yices2.term -> Yices2.model option
(** [solve logic form] solves the Yices2 formula [form].
    [logic] can be "QF_LIA", "QF_LRA"...

    @see <http://yices.csl.sri.com/doc/smt-logics.html> Available logics
*)

val logic_supported : string -> bool
(** Tell if this logic string (e.g., QF_LIA) is supported by Yices2. *)

val enabled : bool
(** Is this library enabled? (requires [yices2] to be installed) *)
