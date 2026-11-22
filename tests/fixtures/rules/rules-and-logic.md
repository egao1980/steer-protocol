---
description: Rule, policy and logical computation goes through policy-protocol / logic-protocol / sat-protocol
# Claude Code
paths:
  - "**/*.lisp"
# Cursor
globs: "**/*.lisp"
alwaysApply: false
---

# Rules and logic go through the logic family

First-party code only. Brief: [cl-stack logic.md](https://github.com/egao1980/cl-stack/blob/main/docs/capabilities/logic.md) (Track L).

| If the code decides… | Use |
|---|---|
| allow / deny / ask, permissions, ACLs, layered settings where deny wins and inner layers tighten | `policy-protocol` (`defpolicy`, `evaluate-policy` + trace) |
| facts derived from other facts: UI enabled/visible/required/valid, dependencies, "what follows from this state" | `logic-protocol` + `logic-backend-datalog` (incremental `update` → delta) |
| next state from the current state (wizards, mode/sandbox state machines) | Datalog time-step rules, model-checked via spec-dsl when it matters |
| pick a choice satisfying constraints (backend selection, configuration) | ASP backend (`logic-backend-asp`), or `sat-protocol` directly |
| pure boolean satisfiability, unsat cores, "can this ever hold" | `sat-protocol` (and the `logic-protocol/sat` bridge for rule analysis) |

- **Don't** add hand-written rule tables, long `cond`/`case` decision chains, or bespoke precedence/merge code for these concerns. Small, local, obviously-total predicates such as `(and (stringp x) (plusp (length x)))` are fine.
- **Explanations are free:** surface the trace or proof ("why was this denied", "why is Submit disabled") instead of building ad hoc messages.
- **Until a protocol is published**, keep new rule code minimal and isolated behind one function so it can migrate. Note it in the owning repo's issue tracker with the `logic-migration` label.
- **Existing rule code migrates** (Track L, L4a–f). Acceptance: the repo's existing tests pass unchanged, plus a new explanation/proof test. cl-repository's solver and source policy are deferred.
