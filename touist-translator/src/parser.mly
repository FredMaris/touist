(*
 * parser.mly: the defition of the menhir incremental parser (using --table --inspection)
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

%{
  open Syntax
%}

%token <int> INT
%token <float> FLOAT
%token <bool> BOOL
%token <string> VAR
%token <string> TERM
%token <string> TUPLE
%token <string> VARTUPLE
%token ADD SUB MUL DIV MOD SQRT TOINT TOFLOAT
%token AND OR XOR IMPLIES EQUIV NOT
%token EQUAL NOTEQUAL LE LT GE GT
%token IN WHEN
%token UNION INTER DIFF SUBSET RANGE
%token EMPTY CARD
%token LBRACK RBRACK
%token LPAREN RPAREN
%token COMMA COLON AFFECT
%token IF THEN ELSE END
%token EXACT ATLEAST ATMOST
%token TOP BOTTOM
%token BIGAND BIGOR
%token BEGIN SETS FORMULA
%token LET
%token EOF

%start <Syntax.prog> prog



(* The following lines define in which order the tokens should
 * be reduced, e.g. it tells the parser to reduce * before +.
 *
 * Note that the precedence rules apply from bottom to top:
 * the top element will be the less prioritized
 *
 * %left: e.g: a PLUS b TIMES -> a PLUS b
 *   The precedence rule applies from left to right,
 *
 * %right:
 *   The precedence rule applies from right to left
 *
 * %noassoc, e.g. NOT(a)
 *   The precedence rule has no direction; this often
 *   applies for unary oparators *)

%right EQUIV IMPLIES (* Lesser priority on precedence *)
%left OR
%left AND
%left XOR
%left NOT
%left IN
%left LE GE LT GT EQUAL NOTEQUAL
%left SUB
%left ADD
%left MUL DIV
%left MOD
%nonassoc high_precedence (* Highest priority on precedence *)

(* This wierd [high_precedence] is not a TERMINAL, not a
 * production rule... It is an arbitrary name that allows
 * to give precedence indications on production rules.
 * Ex:
 *     clause: SUB clause %prec high_precedence
 * will give this production rule a predecence given by
 * where the
 *     %nonassoc high_precedence
 * is written. Here, we want this production rule to be
 * reduced before any other one because it is the "minus" sign,
 * ex:
 *     -3.905
 * and, like
 *     not(a)
 * the minus sign MUST be reduced as fast as possible. *)

%on_error_reduce separated_nonempty_list(COMMA,term_or_exp)
(* %on_error_reduce is a nice "trick" to display a a more accurate
   context when an error is handled. For example, with this text:

       "begin formula formula a(b,c end formula"

   - b is shifted and then reduced thanks to the lookahead ","
   - c is shifted and then reduced thanks to the lookahead "end"
   - end is now evaluated; the parser is still fullfilling the rule
        separated_nonempty_list(COMMA,term_or_exp)                (1)
        -> term_or_exp . COMMA | term_or_exp . RPAREN
     At this moment, the term_or_exp is the "c"; as END does not match
     RPAREN or COMMA, the rule (1) fails to be reduceable.

   The problem is that the $0 token in parser.messages will be
     $0 = end
     $1 = c
     $2 = ,    etc...
   because we were trying to reduce "b (RPAREN | COMMA)".
   There is no way to display the "a" which was the actuall important
   information because we don't actually know on which $i it is.

   %on_error_reduce will actually tell the parser not to fail immediately
   and let the "caller rule" that was calling (1). Here, (1) was called
   twice recursively. The failing rule will hence be

     TERM LPAREN separated_nonempty_list(COMMA,term_or_exp) . RPAREN (2)

   Hence we are sure that $1 will give b,c and $3 will give "a" !
*)


%% (* Everthing below that mark is expected to be a production rule *)
   (* Note that VAR { $0 } is equivalent to v=VAR { v } *)

(* [prog] is the entry point of the parser *)
prog:
  | BEGIN SETS affect* END SETS BEGIN FORMULA clause* END FORMULA EOF
    { Prog (Some $3, $8) }
  | BEGIN FORMULA clause* END FORMULA EOF
    { Prog (None, $3) }

var_decl:
  | VAR { ($1, None) }
  | v=VARTUPLE (*LPAREN*) l=separated_nonempty_list(COMMA, exp) RPAREN { (v, Some l) }
  | v=VARTUPLE (*LPAREN*) l=separated_nonempty_list(COMMA, TERM) RPAREN
    { (v, Some (List.map (fun e -> Term (e,None)) l)) }

affect:
  | var_decl AFFECT exp { Affect ($1, $3) }

exp:
  (* This parametrized rule allows to "regroup" every "clause OPERATOR clause"
    under the same rule. I refactored the explicit rules to that form  to try to
    have clearer messages in parser.messages *)
  | LPAREN exp RPAREN { $2 }
  | INT   { Int   $1 }
  | FLOAT { Float $1 }
  | BOOL  { Bool  $1 }
  | var_decl { Var      $1 }
  | set_decl { Set_decl $1 }
  | SUB exp { Neg $2 } %prec high_precedence
  | exp ADD exp { Add ($1, $3) }
  | exp SUB exp { Sub ($1, $3) }
  | exp MUL exp { Mul ($1, $3) }
  | exp DIV exp { Div ($1, $3) }
  | exp MOD exp { Mod ($1, $3) }
  | SQRT    (*LPAREN*) x=exp RPAREN { Sqrt     x }
  | TOINT   (*LPAREN*) x=exp RPAREN { To_int   x }
  | TOFLOAT (*LPAREN*) x=exp RPAREN { To_float x }
  | exp AND     exp { And     ($1, $3) }
  | exp OR      exp { Or      ($1, $3) }
  | exp XOR     exp { Xor     ($1, $3) }
  | exp IMPLIES exp { Implies ($1, $3) }
  | exp EQUIV   exp { Equiv   ($1, $3) }
  | NOT exp { Not $2 }
  | exp EQUAL    exp { Equal            ($1, $3) }
  | exp NOTEQUAL exp { Not_equal        ($1, $3) }
  | exp LT       exp { Lesser_than      ($1, $3) }
  | exp LE       exp { Lesser_or_equal  ($1, $3) }
  | exp GT       exp { Greater_than     ($1, $3) }
  | exp GE       exp { Greater_or_equal ($1, $3) }
  | exp IN exp { In ($1, $3) }
  | UNION (*LPAREN*) x=exp COMMA y=exp RPAREN { Union (x, y) }
  | INTER (*LPAREN*) x=exp COMMA y=exp RPAREN { Inter (x, y) }
  | DIFF (*LPAREN*) x=exp COMMA y=exp RPAREN { Diff  (x, y) }
  | CARD  (*LPAREN*) x=exp RPAREN { Card  x }
  | EMPTY (*LPAREN*) x=exp RPAREN { Empty x }
  | SUBSET (*LPAREN*) x=exp COMMA y=exp RPAREN { Subset (x, y) }
  | LBRACK exp RANGE exp RBRACK { Range ($2, $4) }
  | IF exp THEN exp ELSE exp END { If ($2, $4, $6) }

(* Redundancy of clause and exp
   ============================
   Because of the need of being able to express SMT clauseulas, the clause and exp
   types are (seemingly) redundant. At first sight, we might think that merging
   clause and exp into a single type would simplify the grammar...
   But clause and exp express two completely different things:
   - an exp will be "computed"; at the end of the touistc translation, its
     result will be reduced to a single float, integer, bool or set.
     An expression of the clause `2+3+$i/5` will give a float.
   - a clause won't be computed, in the sense that the clause
         (x+2 > 0) and not (y-3 != 0)
     will stay the same after touistc translation.
 *)

clause:
  | LPAREN clause RPAREN { $2 }
  | INT   { Int   $1 }
  | FLOAT { Float $1 }

  (* SUB clause makes it really "hard" to solve. Just one example;
     On the first line, the actual list of tokens. On the two following
     lines, two reductions conflicting:
               "clause1 SUB clause2 XOR clause3 ..."
      clause -> clause1 SUB clause2        => ((clause1 SUB clause2) XOR clause3)
      clause ->         SUB clause2        => (clause 1)((SUB clause2) XOR clause3)
   *)
  | SUB clause { Neg $2 } %prec high_precedence
  | clause ADD      clause { Add              ($1, $3) }
  | clause SUB      clause { Sub              ($1, $3) }
  | clause MUL      clause { Mul              ($1, $3) }
  | clause DIV      clause { Div              ($1, $3) }
  | clause EQUAL    clause { Equal            ($1, $3) }
  | clause NOTEQUAL clause { Not_equal        ($1, $3) }
  | clause LT       clause { Lesser_than      ($1, $3) }
  | clause LE       clause { Lesser_or_equal  ($1, $3) }
  | clause GT       clause { Greater_than     ($1, $3) }
  | clause GE       clause { Greater_or_equal ($1, $3) }
  | var_decl { Var $1 }
  | TOP    { Top    }
  | BOTTOM { Bottom }
  | TERM   { Term ($1, None) }
  | t=TUPLE (*LPAREN*) l=separated_nonempty_list(COMMA, term_or_exp) RPAREN
      { Term (t, Some l) }
  | NOT clause { Not $2 }
  | clause AND     clause { And     ($1, $3) }
  | clause OR      clause { Or      ($1, $3) }
  | clause XOR     clause { Xor     ($1, $3) }
  | clause IMPLIES clause { Implies ($1, $3) }
  | clause EQUIV   clause { Equiv   ($1, $3) }
  | EXACT (*LPAREN*) x=exp COMMA y=exp RPAREN { Exact   (x, y) }
  | ATLEAST (*LPAREN*) x=exp COMMA y=exp RPAREN { Atleast (x, y) }
  | ATMOST (*LPAREN*) x=exp COMMA y=exp RPAREN { Atmost  (x, y) }
  | BIGAND separated_nonempty_list(COMMA,VAR) IN separated_nonempty_list(COMMA,exp) COLON clause END
  { Bigand ($2, $4, None, $6) }
  | BIGAND separated_nonempty_list(COMMA,VAR) IN separated_nonempty_list(COMMA,exp) WHEN exp COLON clause END
  { Bigand ($2, $4, Some $6, $8) }
  | BIGOR separated_nonempty_list(COMMA,VAR) IN separated_nonempty_list(COMMA,exp) COLON clause END
  { Bigor ($2, $4, None, $6) }
  | BIGOR separated_nonempty_list(COMMA,VAR) IN separated_nonempty_list(COMMA,exp) WHEN exp COLON clause END
  { Bigor ($2, $4, Some $6, $8) }
  | IF exp THEN clause ELSE clause END { If ($2, $4, $6) }
  | LET v=var_decl AFFECT e=exp COLON c=clause { Let (v,e,c) }

(* Warning: the two rules
     var_decl -> TERM
     exp -> var_decl
   are doing the same thing as term_or_exp *)
term_or_exp:
  | TERM { Term ($1,None) }
  | exp { $1 }

set_decl:
  | LBRACK RBRACK { [] }
  | LBRACK separated_nonempty_list(COMMA, exp) RBRACK { $2 }
  | LBRACK separated_nonempty_list(COMMA, TERM) RBRACK
  { List.map (fun x -> Term (x,None)) $2 }
