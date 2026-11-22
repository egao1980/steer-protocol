---
name: team-solve
description: >-
  Use when implementing a cl-stack Common Lisp feature whose contract is a
  capability brief plus an existing ASDF test-op, or when the user runs
  /team-solve. Fresh agents, an on-disk ledger, and check-feature.sh is the verdict.
---

# team-solve

Ledger method from the [memdoor team-solve steps](https://github.com/guregodevo/memdoor/tree/main/examples/workflows/team-solve/steps) (Apache-2.0). The steps in `steps/` target a cl-stack feature: CLOS protocol or backend in the owning repo, graded by that repo's ASDF test-op.

Not for Python contest problems, refactors with no failing test-op, or reviews.

## Contract

Repo checkout with the `.asd` at its root. `.team-solve/task.md` starts with frontmatter:

```yaml
---
system: cli-protocol
test-system: cli-protocol/tests
brief: ../cl-stack/docs/capabilities/cli.md
---
```

`system` is what `asdf:test-system` runs. `test-system` must already exist. `brief` is optional and read-only. The body is the slice to implement. Locked decisions in the brief stay locked.

`tests/` is the spec. Solver and repair do not edit `tests/`, `task.md`, or the brief. They do not delete or skip assertions. Ledger files stay in `.team-solve/` and are not committed.

## Coordinator

Dispatch and run seal, test, and verify. Do not plan, ideate, implement, review, or repair. Do not edit Lisp, `tests/`, `task.md`, or the brief.

Refuse to start unless `.team-solve/task.md` has `system` and `test-system`, and the checkout root has the `.asd`. Refuse if any of these already exist: `.team-solve/plan.md`, `notes.md`, `review.md`, `contract.sha256`, `test-output.log`, `test-status.txt`, `final-test-output.log`.

Seal first, from the repo root. `$CHECK` is the absolute path of `check-feature.sh` next to this file.

```bash
bash "$CHECK" --seal
```

Run id: `team-solve-YYYYMMDDHHMMSS`. Replace `{{.partition}}` in the plan prompt with that id. Nowhere else.

Each agent step is one fresh subagent (Claude Code: Agent tool, `general-purpose`; Cursor: Task, `generalPurpose`). Do not `resume`. The task text is the step `prompt` plus these lines and nothing else:

```
Repo: <absolute path of the checkout>
Ledger: <absolute path>/.team-solve
Paths in the prompt are relative to the repo root.
Workspace skills, read before editing Lisp: <workspace>/.lisp-workspace/skills/asdf/SKILL.md, cl-unit-testing/SKILL.md, cl-stack-conditions/SKILL.md, cl-repository-ci/SKILL.md
```

No hints and no earlier replies. Workers must not spawn agents. `ideate-a` and `ideate-b` go out together, in one message, after `plan`.

`max_retries: 1` is one re-dispatch of that step when its files are missing. It is not a second repair.

## Order

| step | kind | after | done when |
| --- | --- | --- | --- |
| seal | command | — | `.team-solve/contract.sha256` exists |
| `plan` | agent | seal | `plan.md` and `notes.md` exist; `<!-- proposal-a -->` and `<!-- proposal-b -->` each occur once |
| `ideate-a`, `ideate-b` | agents, parallel | plan | proposal text sits immediately before its own marker |
| `solve` | agent | both ideators | implementation is in the repo; the solver decision is in `notes.md`; `tests/` is untouched |
| `test` | command | solve | `test-status.txt` and `test-output.log` exist. A nonzero status does not stop the run |
| `review` | agent | test | `review.md` exists |
| `repair` | agent | review | exactly one pass, including when the status is 0 |
| `verify` | command | repair | this exit status is the workflow result |

## Commands

From the repo root.

Test, and keep going:

```bash
bash "$CHECK" > .team-solve/test-output.log 2>&1
result=$?
printf '%s\n' "$result" > .team-solve/test-status.txt
cat .team-solve/test-output.log
printf 'Initial test-op exit status: %s\n' "$result"
```

Verify. Do not repair again if this fails. Report the log.

```bash
bash "$CHECK" > .team-solve/final-test-output.log 2>&1
result=$?
cat .team-solve/final-test-output.log
exit "$result"
```

A model saying done is not success. `verify` exit 0 is success. A contract hash mismatch fails the run before Lisp starts.

## Checker

`bash .lisp-workspace/skills/team-solve/test-checker.sh` from the workspace root. The fixture is a one-variable system, not a stack feature.

The verdict runs `cl-repo test --system <system>` in the repo root when `cl-repo` is on PATH, so dependencies come from GHCR. Without the client it falls back to `run-test.lisp` under `ros +Q` (no Quicklisp; `-Q` turns it on). `TEAM_SOLVE_RUNNER=lisp` forces the fallback; the self-test passes with either runner.
