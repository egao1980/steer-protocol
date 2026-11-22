---
name: cl-stack-conditions
description: >-
  CLHS 9 conditions + restarts for first-party cl-stack. Use when defining errors,
  handler-bind / restart-case, or wrapping usocket/dexador/lparallel. No private error dialect.
---

# cl-stack conditions & restarts

Required for first-party **cl-stack** (`*-protocol`, `*-backend-*`, `cl-stack-*`). Not third-party forks.

The language **is** the library: [CLHS 9](http://www.lispworks.com/documentation/HyperSpec/Body/09_.htm). Read [PCL ch.19](https://gigamonkeys.com/book/beyond-exception-handling-conditions-and-restarts) and the [Cookbook](https://lispcookbook.github.io/cl-cookbook/error_handling.html) before inventing helpers.

## Law

1. **Signal a condition.** Do not return status codes, `(values nil err)`, or exception-shaped plists as the sole failure path.
2. **Three-way split** (Pitman / PCL): detection signals; the lowest frame that can recover establishes **restarts**; callers install **policy** with `handler-bind`.
3. **Standard names first.** [CLHS restart functions](http://clhs.lisp.se/Body/f_abortc.htm): `abort`, `continue`, `muffle-warning`, `store-value`, `use-value`. Call those functions. Do not shadow their semantics.
4. **Reuse prior art.** CL built-ins, Alexandria, UIOP/ASDF, usocket, dexador, lparallel, and existing stack taxonomies. Do not wrap them away.

## Signal

| Form | When |
|------|------|
| `error` | Failure; debugger if unhandled |
| `cerror` | Continueable — establishes **`continue`** |
| `signal` | Non-serious / control (`mcp-input-required`). Unhandled → proceeds |
| `warn` | Warning; **`muffle-warning`** |
| `check-type` / `assert` | Already offer **`store-value`** (and `assert` **`continue`**) |

```lisp
(define-condition path-not-found (path-error)
  ((path :initarg :path :reader path-error-path))
  (:report (lambda (c s)
             (format s "Path not found: ~S" (path-error-path c)))))

(error 'path-not-found :path path)   ; or (cerror "Ignore and proceed" '…)
```

Root type `foo-error` (`error`); subclasses for cases handlers distinguish. Slots + readers + `:report`. `make-condition` if you must; usually `error`/`signal` construct. Protocol owns the types; backends **signal** them (do not invent a parallel backend error tree).

Wire / HTTP / RPC codes are **slots**. Handlers bind on **type** (`a2a-task-not-found`), not integers. See `a2a-protocol/src/conditions.lisp`.

Non-error control = `(define-condition … (condition))` + `signal` — `mcp-input-required`. Do not subclass `error` if the default is “keep going”.

## Restarts

Establish at the **lowest** site that can actually recover (PCL: `skip-log-entry` lives where returning NIL is valid; not inside the parser that must not return NIL).

Prefer `restart-case` (associates restarts with the condition when the form is `error`/`cerror`/`signal`/`warn`). `with-simple-restart` for a single named escape. `restart-bind` only when the restart function must **not** unwind.

```lisp
(restart-case (error 'path-not-found :path path)
  (use-value (value)
    :report "Use a supplied value instead"
    :interactive (lambda ()
                   (format *query-io* "Value: ")
                   (force-output *query-io*)
                   (list (read *query-io*)))
    value)
  (ignore-missing ()
    :report "Treat missing path as success"
    nil))
```

| Name | Source | Invoke |
|------|--------|--------|
| `use-value` | CLHS | `(use-value x [condition])` |
| `store-value` | CLHS (`check-type`) | `(store-value x [condition])` |
| `continue` | CLHS (`cerror`) | `(continue [condition])` |
| `abort` | CLHS | `(abort [condition])` |
| `muffle-warning` | CLHS | `(muffle-warning [condition])` |
| `retry` | **ASDF** convention, not a CLHS function | `(invoke-restart 'retry)` — `tagbody`/`loop` around the op |
| domain (`create-parents`, `skip`, `provide-input`) | when the recovery is its own API | `(invoke-restart 'create-parents)` |

`:report` always. `:interactive` if a human can supply args. `:test` to hide inapplicable restarts.

**Do not** collapse a distinct recovery into `(use-value nil)` (PCL: that couples policy to internals). **Do not** invent `invoke-use-value` as the advertised API when `use-value` exists. Existing stack `invoke-*` / `auto-*` / `with-auto-*` (pathlib, mcp, a2a, llm) are thin sugar over `find-restart` — optional, not a second protocol. New code may add sugar; it must not replace CLHS names or hide `handler-bind`.

`retry` at the **operation** boundary (`tagbody` + `go`, as pathlib / ASDF); mutating recoveries (`create-parents`) run then invoke `retry`.

## Handlers

```lisp
;; Policy — stack still live
(handler-bind ((path-not-found
                (lambda (c)
                  (use-value #() c))))
  (read-bytes path))

;; Unwind / translate only
(handler-case (parse-card json)
  (a2a-error (c) (translate-to-rpc c)))
```

- `handler-bind` → invoke a restart or decline (return). This is the default for recoveries.
- `handler-case` → unwind, then run a clause. Translation, “skip this item”, tests.
- Library code: no `ignore-errors`, no `(handler-case … (error …))`, no `serious-condition` mop-up.
- Policy (retry-3, skip, default) lives in the **caller / facade / `with-auto-*`**, not inside the primitive that signals.
- Handlers are per-thread. A `handler-bind` around `run` / `drain-agenda` does not see worker (KSAR, pool) conditions — establish restarts at the worker site and install default policy in `spawn-*`. A worker `handler-case` that logs and keeps going makes a mid-pipeline death look like idle.

## Well-known libraries

Do not reimplement these. Handle or wrap them.

| Prior art | Use |
|-----------|-----|
| `check-type`, `assert` | Type/invariant failures; keep their restarts |
| **Alexandria** | `required-argument`; `simple-parse-error` / `simple-program-error`; `ignore-some-conditions` for **named benign** types only; `unwind-protect-case` when abort vs normal cleanup differs |
| **UIOP** | `uiop:parameter-error`; `uiop:with-muffled-conditions` / compile muffling — do not roll a private muffle |
| **ASDF** | `retry` around compile/load — same name if the op is retried |
| **usocket** | `usocket:timeout-error`, `connection-refused-error`, `ns-try-again-condition`, … — bind those types; don't swallow as `error` |
| **dexador** (maintenance HTTP) | `dexador.error:http-request-failed` hierarchy — map to `http-protocol` conditions; keep the original as `:cause` if you wrap |
| **lparallel** | `lparallel:task-handler-bind`, `invoke-transfer-error` — raw `handler-bind` does not see worker-thread conditions |
| **Rove** | `ok (signals form 'foo-error)`. Do **not** nest a restarting form inside `ok` — Rove `handler-case`s first (`cl-stack-pathlib/tests/restarts-test.lisp`) |

Wrapping a foreign condition into a protocol type is fine when the facade contract needs it. Keep slots (`:cause`, status, path). Do not drop the original type on the floor.

## Stack prior art (match when adding)

- Taxonomy: `http-protocol`, `event-protocol`, `rpc-protocol` — root + subclasses + slots; older files may lack restarts — **add them when you touch the error path**, don't retrofit everything in one pass.
- Pathlib shape: domain restarts at the **signal** site + `retry` at the **op** site; `auto-*` + `with-auto-*` as optional policy macros. Same idea in mcp / a2a / ag-ui / llm / blackboard.
- `mcp-input-required`: non-error `signal` + `provide-input` / `decline-input`.
- Capability: `skip` / `use-value` on unknown names.

## Tests

```lisp
(ok (signals (mkdir "/x/y" :parents nil) 'missing-parent))

(handler-bind ((missing-parent (lambda (c)
                                 (invoke-restart 'create-parents))))
  (with-path-restarts
    (mkdir "/x/y" :parents nil)))
```

Cover unhandled signal **and** at least one restart path for each public recovery.

Domain restart names are symbols in the protocol package; CLHS ones (`use-value`, `continue`, `abort`) are not. From a test package use the `invoke-*` sugar or `protocol::name` — under `(:use :rove)`, `(invoke-restart 'skip)` names `rove:skip` → "No restart".

## Anti-patterns

- Status codes / `nil`+stderr as the only error channel
- Java/Python wrap-and-rethrow that strips slots and restarts
- Shadowing `use-value` / `continue` with different meaning
- `handler-case` + recursive retry instead of a `retry` restart
- Catch-all `error` in a backend to “keep the server up”
- Stringly `:reason` with no subclass when callers must branch
- Putting retry/skip policy inside the protocol GF default method
- A new conditions utility library — CLHS + Alexandria + UIOP are enough

## Checklist

- [ ] Condition type in the **protocol** package, exported, slotted, `:report`
- [ ] Restarts named per CLHS/ASDF/domain-API rules, associated with the condition
- [ ] Policy is `handler-bind` above the primitive
- [ ] Foreign library conditions handled by **their** types (or wrapped with `:cause`)
- [ ] Tests: `signals` + one programmatic restart
