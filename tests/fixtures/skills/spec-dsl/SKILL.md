---
name: spec-dsl
description: >-
  cl-stack formal-spec DSL: `spec-protocol` (`defspec` = CLOS protocol + spec AST, FSet runtime,
  ITF traces, MBT replay) + `spec-backend-quint` (emit .qnt, drive quint typecheck/run/test/verify/compile).
  Use when writing a `defspec`, adding contracts (:requires/:guard/:ensures), emitting Quint or TLA+
  from Lisp, adding a spec backend, or wiring golden `.qnt` / ITF fixtures into Rove.
  Quint language itself: quint-modeling. Replay: spec-mbt-conformance.
---

# spec-dsl (`spec-protocol` + `spec-backend-quint`)

**One `defspec` = CLOS protocol + formal spec.** The form expands to a class (vars = slots, consts = initargs), generics + methods (actions, vals, defs), `deftype`s (sum types), `check-invariants`, **and** registers the AST that `spec-backend-quint` emits as `.qnt`. Do not write a model beside the code; the model is the code's core.

`spec-protocol` (nickname `stack-spec`) owns DSL, AST, CLOS projection, conditions, backend generics; packages `spec-protocol.itf` (ADR-015 traces) and `spec-protocol.mbt` (replay). `spec-backend-quint` emits and shells out to `quint` via `process-protocol`. TLA+ text: `(compile-spec m :target :tlaplus)` (Apalache, needs Java). Repos: `egao1980/spec-protocol`, `egao1980/spec-backend-quint`.

```lisp
(asdf:load-system "spec-backend-quint")   ; + process-backend-uiop, json-backend-jzon
(emit 'bank) (typecheck 'bank) (run-tests 'bank)
(simulate 'bank :invariants '(no-negatives) :seed 1 :n-traces 3 :max-steps 10)   ; --mbt traces
(verify 'bank :max-steps 5 :checker :apalache)                                    ; or :tlc
```

## `defspec` shape

```lisp
(defspec bank (:module "Bank" :instance ("BankTest" (accounts (set "a" "b"))))
  (const accounts (set str))
  (type status (or :idle (busy int)))              ; sum type = CL `or` type-spec; keywords = nullary
  (var balances (map str int))
  (var status status)
  (pure-def can-withdraw ((b int) (n int)) (:returns bool) (>= (- b n) 0))
  (val total (fold (keys balances) 0 (lambda (acc k) (+ acc (get balances k)))))
  (action init (setf balances (map-of ((k accounts)) 0) status :idle))
  (action deposit ((who str) (n int))
    (:requires (in who accounts) (> n 0))          ; caller obligation
    (:ensures (= total (+ (old total) n)))         ; post-state, (old …) = pre-state
    (setf balances (put balances who (+ (get balances who) n)) status (busy n)))
  (action withdraw ((who str) (n int))
    (:guard (can-withdraw (get balances who) n))   ; enabling condition
    (setf balances (put balances who (- (get balances who) n)))
    (setf status (match status ((busy k) (busy (+ k n))) (_ :idle))))
  (invariant no-negatives (forall accounts (lambda (a) (>= (get balances a) 0))))
  (:spec-only
   (action step (nondet (who (one-of accounts)) (nondet (n (one-of (to 1 5))) (any (deposit who n) (withdraw who n)))))
   (temporal eventually-busy (eventually (/= status :idle)))
   (run happy-test (expect (then (then init (deposit "a" 3)) (withdraw "a" 1)) (= (get balances "a") 2)))))
```

Decl heads: `const var type import assume pure-val pure-def val def action invariant witness temporal run`. Header: `:module`, `:instance ("Name" (const expr)…)` (required when there are consts — Quint cannot run a module with unbound consts; hosts the `run`s; default `--main`), `:doc`, `:class`, `:superclasses`, `:accessor-prefix`, `:clos nil`. `:as "Literal"` on a decl overrides the emitted name. Several body forms in an action = implicit `(all …)`. Params `(who n)` or `((who str) (n int))`; annotated params need `(:returns T)` (actions are `bool`) or the annotations are dropped from Quint (CL keeps `declare`).

Toplevel extension (redefinable like `defmethod`): `(defaction bank reset () (:guard …) body)`, `(definvariant bank name expr)`, `(defrun bank name expr)`, `(defspec-decl bank (decl …))`.

## Forms → Quint

| Lisp | Quint |
|------|-------|
| `(+ a b)` `(= a b)` `(/= a b)` `(and …)` `(or …)` `(not a)` `(implies a b)` `(iff a b)` | infix / `not(a)` / `a.implies(b)` — nested binaries parenthesised |
| `(setf x e …)` `(incf x [n])` `(decf x [n])` | `x' = e` (actions only; simultaneous) |
| `(union a b)` `(in x s)` `(size s)` `(fold s init f)` `(map s f)` `(filter s f)` `(exists s f)` `(forall s f)` `(to a b)` `(get m k)` `(put m k v)` `(set-by m k f)` `(keys m)` `(map-by s f)` `(append l x)` `(head l)` `(tail l)` `(length l)` `(nth l i)` `(foldl l init f)` `(select l f)` | method style `a.union(b)` … |
| `(all …)` `(any …)` `(nondet (v (one-of s)) body)` | `all {}` / `any {}` / `nondet v = s.oneOf()` |
| `(if c a [b])` `(let ((v e)) body)` `(lambda (x y) body)` `(match e ((busy n) body) (:idle body) (_ body))` | `if (c) a else b` / `val v = e` / `((x, y) => body)` / `match e { \| Busy(n) => … \| Idle => … \| _ => … }` |
| `(set …)` `(list …)` `(tuple …)` `(map-lit (k v) …)` `(rec (a 1) (b 2))` `(field r a)` `(with r a v)` `(item tup 1)` `(map-of ((k s)) v)` | `Set(…)` `[…]` `(…)` `Map(k -> v)` `{ a: 1, b: 2 }` `r.a` `r.with("a", v)` `tup._1` `s.mapBy(k => v)` |
| `t` `nil` ints strings keywords `(busy 3)` | `true` `false` … `Idle` `Busy(3)` |
| `(:raw "text")` spec-only · `(:lisp form)` CL-only | escape hatches — drift points, last resort |

Types: `int str bool`, `(set T)` `(list T)` `(map K V)` `(tuple …)` `(rec (f T) …)`, `(or :a (b T))`, declared names.

Names mangle deterministically: kebab → `camelCase` (vars, consts, ops, params, fields), `PascalCase` (types, labels); `windows-bounded-6-9-1` → `windowsBounded_6_9_1`. `demangle-name` inverts (ITF names, last `::` segment).

## CLOS projection

- Action body: `:requires` false ⇒ `spec-precondition-error` (`continue` proceeds); `:guard` false ⇒ `spec-action-disabled` (`continue` = no-op, returns NIL); bare boolean forms in the body are guards too; `setf`s are **simultaneous** (all RHS in pre-state, one commit); `:ensures` ⇒ `spec-postcondition-error`; then `check-invariants` when `*check-invariants*` ⇒ `spec-invariant-violation` (`continue`). Action returns T when applied.
- Quint requires every var assigned per step; the emitter adds `v' = v` frame conditions per branch, so actions state only what changes. Missing `else` in an action = no-op.
- Values: `t`/`nil`; `fset2:set` / `fset2:map` / `fset2:seq` (`spec-set` `spec-map` `spec-seq`); tuples = lists; records = canonical keyword plists (`rec`); variants = keyword or `(label . value)`; `spec-equal`. Runtime ops `make-set set-in-p map-get map-put seq-append …` are what `(get m k)` etc. compile to.
- `self` (interned in the spec's package) is the state parameter — usable in `(:lisp …)`. `spec-state-alist`, `spec-state-get/set`, `apply-action`, `spec-copy-state`, `print-object` show vars.
- Parse/expansion errors are `spec-parse-error` (restart `use-value`) at macroexpansion: `setf` outside an action, `nondet`/`any`/`one-of`/`:raw`/action calls outside `(:spec-only …)`, unknown names.

## Driver

`*spec-backend*` + facades `emit typecheck simulate verify run-tests compile-spec check` over generics `backend-emit backend-typecheck backend-simulate backend-verify backend-run-tests backend-compile`. `spec-result`: `result-status` (`:ok :violation :error`), `result-tool`, `result-seed`, `result-errors` (ADR-002 strings), `result-traces` (`itf-trace`s), `result-passed`/`result-failed`, `result-output`. `check` signals `spec-invariant-violation` (`continue`) on `:violation`. `spec-tool-missing-error` when quint is absent. Quint backend: `QUINT_BIN`, `JAVA_HOME` (verify / TLA+), `use-quint-backend :directory :keep-files`.

## Fixtures + tests (Rove via OCI `egao1980/rove`)

- Golden emit: `tests/fixtures/<spec>.qnt` `string=` to `(emit-to-string spec)`; regenerate with `emit`, never by hand.
- Frozen traces: `(simulate … :seed N)` → `spec-protocol.itf:write-itf` into `tests/fixtures/*.itf.json`; replay in CI without Node (skill **spec-mbt-conformance**). Keep a trace from a deliberately broken variant to prove divergence is detected.
- Gate: `(unless (quint-available-p) (skip "quint not installed"))`; Java-dependent (`verify`, `compile :tlaplus`) on `(java-available-p)`.
- Local OCI run: `CL_REPO_SYSTEM=spec-protocol CL_SOURCE_REGISTRY="$PWD/spec-protocol//:" sbcl --load .lisp-workspace/scripts/oci-test-system.lisp`. Pin API-bearing deps with `(:version "cl-stack-pathlib" "0.3.0")`; a stale older version in `~/.local/share/cl-repository/systems/` shadows the pin locally — delete it.
- Table tests: `deftest-parametrize` rows are **evaluated** — quote symbols.

## Where a model lives

Model + driver for protocol `foo` = `spec/` in the `foo` repo (subsystem `foo/spec`, deps `spec-protocol`), generated class as mixin / delegate core; tests in `foo/tests`; `:cl-repo (:ci (:with ("foo/spec")))`. Shared examples in `spec-protocol/src/examples`. Not in `*-parity` (interop canaries).

## Anti-patterns

- Hand-editing emitted `.qnt` or fixtures
- `true`/`false` symbols (unknown names) — booleans are `t`/`nil`
- `(| …)` for sum types — `|` is the reader's multiple-escape; use `(or …)`
- `(:raw …)` / `(:lisp …)` for anything the forms table covers — extend the table
- Modelling the code's quirks instead of the spec; the replay is where quirks surface
- Tests that need Node or Java to pass
