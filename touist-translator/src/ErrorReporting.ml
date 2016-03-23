(**************************************************************************)
(*                                                                        *)
(*  Menhir                                                                *)
(*                                                                        *)
(*  François Pottier, INRIA Paris-Rocquencourt                            *)
(*  Yann Régis-Gianas, PPS, Université Paris Diderot                      *)
(*                                                                        *)
(*  Copyright 2005-2015 Institut National de Recherche en Informatique    *)
(*  et en Automatique. All rights reserved. This file is distributed      *)
(*  under the terms of the Q Public License version 1.0, with the change  *)
(*  described in file LICENSE.                                            *)
(*                                                                        *)
(**************************************************************************)

(*
 * error_reporting.ml
 * Copyright (C) 2016 Maël Valais <mael.valais@gmail.com>
 *
 * Distributed under terms of the MIT license.
 *)



module Make
  (I : MenhirLib.IncrementalEngine.EVERYTHING)
  (User : sig

    (* In order to submit artificial tokens to the parser, we need a function
       that converts a terminal symbol to a token. Unfortunately, we cannot
       (in general) auto-generate this code, because it requires making up
       semantic values of arbitrary OCaml types. *)

    val terminal2token: _ I.terminal -> I.token

  end)
= struct

  open MenhirLib.General
  open I
  open User

  (* ------------------------------------------------------------------------ *)

  (* Explanations. *)

  type explanation = {
    item: item;
    past: (xsymbol * Lexing.position * Lexing.position) list
  }

  let item explanation =
    explanation.item

  let past explanation =
    explanation.past

  let future explanation =
    let prod, index = explanation.item in
    let rhs = rhs prod in
    drop index rhs

  let goal explanation =
    let prod, _ = explanation.item in
    lhs prod

  (* ------------------------------------------------------------------------ *)

  (* [items_current env] assumes that [env] is not an initial state (which
     implies that the stack is non-empty). Under this assumption, it extracts
     the automaton's current state, i.e., the LR(1) state found in the top
     stack cell. It then goes through [items] so as to obtain the LR(0) items
     associated with this state. *)

  let items_current env : item list =
    (* Get the current state. *)
    match Lazy.force (stack env) with
    | Nil ->
        (* If we get here, then the stack is empty, which means the parser
           is in an initial state. This should not happen. *)
        invalid_arg "items_current" (* TEMPORARY it DOES happen! *)
    | Cons (Element (current, _, _, _), _) ->
        (* Extract the current state out of the top stack element, and
           convert it to a set of LR(0) items. Returning a set of items
           instead of an ['a lr1state] is convenient; returning [current]
           would require wrapping it in an existential type. *)
        items current

  (* [is_shift_item t item] determines whether [item] justifies a shift
     transition along the terminal symbol [t]. *)

  let is_shift_item (t : _ terminal) (prod, index) : bool =
    let rhs = rhs prod in
    let length = List.length rhs in
    assert (0 < index && index <= length);
    (* We test that there is one symbol after the bullet and this symbol
       is [t] or can generate a word that begins with [t]. (Note that we
       don't need to worry about the case where this symbol is nullable
       and [t] is generated by the following symbol. In that situation,
       we would have to reduce before we can shift [t].) *)
    index < length && xfirst (List.nth rhs index) t

  let compare_explanations x1 x2 =
    let c = compare_items x1.item x2.item in
    (* TEMPORARY checking that if [c] is 0 then the positions are the same *)
    assert (
      c <> 0 || List.for_all2 (fun (_, start1, end1) (_, start2, end2) ->
        start1.Lexing.pos_cnum = start2.Lexing.pos_cnum &&
        end1.Lexing.pos_cnum = end2.Lexing.pos_cnum
      ) x1.past x2.past
    );
    c

  (* [marry past stack] TEMPORARY comment *)

  let rec marry past stack =
    match past, stack with
    | [], _ ->
        []
    | symbol :: past, lazy (Cons (Element (s, _, startp, endp), stack)) ->
        assert (compare_symbols symbol (X (incoming_symbol s)) = 0);
        (symbol, startp, endp) :: marry past stack
    | _ :: _, lazy Nil ->
        assert false

  (* [accumulate t env explanations] is called if the parser decides to shift
     the test token [t]. The parameter [env] describes the parser configuration
     before it shifts this token. (Some reductions have taken place.) We use the
     shift items found in [env] to produce new explanations. *)

  let accumulate (t : _ terminal) env explanations =
    (* The parser is about to shift, which means it is willing to
       consume the terminal symbol [t]. In the state before the
       transition, look at the items that justify shifting [t].
       We view these items as explanations: they explain what
       we have read and what we expect to read. *)
    let stack = stack env in
    List.fold_left (fun explanations item ->
      if is_shift_item t item then
        let prod, index = item in
        let rhs = rhs prod in
        {
          item = item;
          past = List.rev (marry (List.rev (take index rhs)) stack)
        } :: explanations
      else
        explanations
    ) explanations (items_current env)
      (* TEMPORARY [env] may be an initial state!
         violating [item_current]'s precondition *)

  (* [investigate pos checkpoint] assumes that [checkpoint] is of the form
     [InputNeeded _].  For every terminal symbol [t], it investigates
     how the parser reacts when fed the symbol [t], and returns a list
     of explanations. The position [pos] is where a syntax error was
     detected; it is used when manufacturing dummy tokens. This is
     important because the position of the dummy token may end up in
     the explanations that we produce. *)

  let investigate pos (checkpoint : _ checkpoint) : explanation list =
    weed compare_explanations (
      foreach_terminal_but_error (fun symbol explanations ->
        match symbol with
        | X (N _) -> assert false
        | X (T t) ->
            (* Build a dummy token for the terminal symbol [t]. *)
            let token = (terminal2token t, pos, pos) in
            (* Submit it to the parser. Accumulate explanations. *)
            let checkpoint = offer checkpoint token in
            I.loop_test (accumulate t) checkpoint explanations
      ) []
    )

  (* We drive the parser in the usual way, but records the last [InputNeeded]
     checkpoint. If a syntax error is detected, we go back to this checkpoint
     and analyze it in order to produce a meaningful diagnostic. *)

  exception Error of (Lexing.position * Lexing.position) * explanation list

  let entry (start : 'a I.checkpoint) lexer lexbuf =
    let fail (inputneeded : 'a I.checkpoint) (checkpoint : 'a I.checkpoint) =
      (* The parser signals a syntax error. Note the position of the
         problematic token, which is useful. Then, go back to the
         last [InputNeeded] checkpoint and investigate. *)
      match checkpoint with
      | HandlingError env ->
          let (startp, _) as positions = positions env in
          raise (Error (positions, investigate startp inputneeded))
      | _ ->
          assert false
    in
    I.loop_handle_undo
      (fun v -> v)
      fail
      (lexer_lexbuf_to_supplier lexer lexbuf)
      start

  (* TEMPORARY could also publish a list of the terminal symbols that
     do not cause an error *)

end
