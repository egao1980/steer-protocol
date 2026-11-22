---
description: Idiomatic CL conditions and restarts for first-party cl-stack Lisp
# Claude Code
paths:
  - "**/*.lisp"
# Cursor
globs: "**/*.lisp"
alwaysApply: false
---

# cl-stack conditions & restarts

First-party only (`*-protocol`, `*-backend-*`, `cl-stack-*`). Language = [CLHS 9](http://www.lispworks.com/documentation/HyperSpec/Body/09_.htm). Full skill: **cl-stack-conditions**.

- Signal at detection; restarts at the lowest recoverable site; policy in `handler-bind` above.
- Standard names first: `abort`, `continue`, `muffle-warning`, `store-value`, `use-value`. Domain names only when the recovery is its own API. `retry` = ASDF → `invoke-restart`.
- `handler-bind` to invoke restarts. `handler-case` only to unwind/translate. No `ignore-errors` / catch-all `error` in library code.
- Typed `foo-error` tree + slots + `:report`. Protocol owns types; backends signal them. Wire codes are slots.
- Reuse usocket / dexador / UIOP / Alexandria / lparallel types; wrap with `:cause` if needed.
