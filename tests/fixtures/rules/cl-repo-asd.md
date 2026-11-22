---
description: New .asd — no :cl-repo unless overlays; :oci is the implied dep source
# Claude Code
paths:
  - "**/*.asd"
# Cursor
globs: "**/*.asd"
alwaysApply: false
---

# New first-party `.asd`

`:depends-on` is fetched from OCI by default. Do not pin sources.

- **Source-only:** honest `:version` / `:depends-on` / `foo/tests`. **No** `:properties (:cl-repo …)`.
- **Natives:** then `:cl-repo` with `:overlays` / `:cffi-libraries`.
- **Never** `:sources (("foo" :oci))` — that restates the default.
- **Never** `:sources (("foo" :ql))`.

Skill **asdf**.
