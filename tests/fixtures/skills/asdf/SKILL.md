---
name: asdf
description: >-
  ASDF 3: defsystem, new first-party .asd shape, load/test-system, source
  registry. Use when writing a new system, editing :depends-on / :cl-repo /
  :sources, "component not found", or CL_SOURCE_REGISTRY.
---

# ASDF (Another System Definition Facility)

Manual: [asdf.common-lisp.dev](https://asdf.common-lisp.dev/asdf.html) (ASDF 3.x).

## New first-party system

`:oci` is the implied source for `:depends-on`. Do **not** write `:sources`.

```lisp
(defsystem "foo"
  :version "0.1.0"
  :depends-on ("bar" "baz")
  ;; no :properties (:cl-repo …) — source-only
  :in-order-to ((test-op (test-op "foo/tests"))))
```

Add `:properties (:cl-repo …)` **only** for native overlays (`:overlays` / `:cffi-libraries`). Never `:sources (("bar" :oci))`. Tests: **cl-unit-testing**. Publish: **cl-repository-ci**.

Then **create `egao1980/<name>` the same day** (`../../scripts/create-first-party-repo.sh`). No owning repo ⇒ never on GHCR. Workspace-only protocol/backend trees are forbidden.

## Core concepts

- **System** — defined with **`defsystem`** in a `.asd` file; **`asdf:load-system`** / **`asdf:find-system`**.
- **Dependencies** — `:depends-on`, `:defsystem-depends-on`, `:serial t`, module/component tree.
- **Tests** — many projects expose **`asdf:test-system`** (often depends on FiveAM, Rove, etc.).

## Finding systems

- **Per-user config:** `~/.config/common-lisp/source-registry.conf.d/*.conf` (XDG) — `:source-registry` with `:tree` or `:directory` and **`:inherit-configuration`**.
- **Env:** `CL_SOURCE_REGISTRY` can supply the same s-expression ([Configuring ASDF](https://asdf.common-lisp.dev/asdf.html#Configuring-ASDF)).
- This workspace: `.lisp-workspace/scripts/add-cl-project.sh` writes **`50-lisp-workspace-<name>.conf`** for each added project.

## Operations

- **`asdf:load-system`**, **`asdf:compile-system`**, **`asdf:operate`**, **`asdf:system-source-directory`** — use when explaining build/test flows.

## Pitfalls

- Nested trees (e.g. `.qlot/`) under a single `:tree` can register duplicate system names — prefer per-project **qlot** isolation or narrow registry entries.
- **`:defsystem-depends-on`** is resolved at **parse time** — ASDF must be able to `find-system` those dependencies before the `defsystem` form is processed. If a `:defsystem-depends-on` target is not in any known source registry or Quicklisp dist, the entire `.asd` file fails to load. Pre-install such systems before loading the `.asd` (e.g. `(ql:quickload :deploy)` before `ros install lem-project/lem`).
- Top-level forms in `.asd` files (outside `defsystem`) execute during `load-asd`. Some projects use this to run `qlot install --no-deps` or load setup files. These side effects can conflict with Roswell's or ASDF's own session state.
