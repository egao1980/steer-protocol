# steer-protocol

Lispy **CLOS** rules / skills for [cl-stack](https://github.com/egao1980/cl-stack). One directive type, `:kind` `:rule` or `:skill`. **0.2** adds tool-bearing skills and a versioned skill store.

**Not** A2A `agent-skill` (card advertisement). **Not** GFs on `llm-protocol`. **Not** RAG. No `ai-agent-protocol` dependency — tool *descriptors* are `llm-protocol:llm-tool`.

| System | Role | Repo |
|--------|------|------|
| `steer-protocol` (`stack-steer`) | Protocol + in-memory source + `SKILL.md` loader + skill store | this repo |

```lisp
(asdf:load-system "steer-protocol")

(let ((src (stack-steer:make-in-memory-steering
            (list (stack-steer:make-steer-rule "cite" :body "Always cite.")
                  (stack-steer:load-skill #p"skills/review/SKILL.md")))))
  (stack-steer:apply-steering "review this" src))
```

| Role | GF | In-tree |
|------|----|---------|
| `steering-source` | `list-directives` / `find-directive` / `register-directive` / `unregister-directive` | `in-memory-steering` |
| compile | `compile-steering` → system-prompt string | enabled directives only |
| apply | `apply-steering` | merge into a `:system` turn |
| files | `parse-skill-markdown` / `load-skill` / `load-skills-from-directory` | Cursor/Codex `SKILL.md` frontmatter + `## tools` |
| tools | `skill-tools` / `skill-tool-fn` / `register-skill-tool-fn` | `llm-tool` descriptors + extra fns |
| store | `save-skill-version` / `skill-versions` / `rollback-skill` / `load-skill-version` | `file-skill-store`, `git-skill-store` |

Wire an agent with `:steering` (`ai-agent-protocol` **0.2.2**). `prepare-agent-turns` applies after memory recall. `make-skill-tool-source` on the agent lists `skill-tools` and dispatches `skill-tool-fn`.

Missing source → `steer-missing-source` (`use-value`). Unknown name → `steer-unknown-directive` (`use-value` / `continue`). Missing file → `steer-skill-not-found` (`use-value`). Unknown store version → `steer-unknown-version` (`use-value` / `continue`).

## Tool-bearing skills

`SKILL.md` may list tools in frontmatter (`tools: lookup, grep`) and/or a markdown section:

```markdown
---
name: review
description: Review a change
tools: lookup, grep
---

Check tests and cite sources.

## tools
### lookup
description: Look up a symbol
name: lookup
### grep
description: Search the tree
```

`(skill-tools skill)` → list of `llm-protocol:llm-tool` (name, description, parameters string/plist). `(skill-tool-fn skill name)` → function or symbol. Register implementations with `register-skill-tool-fn`, or put a name → fn plist on `steer-directive-extra` as `:tools`.

## Versioned skill store

`(save-skill-version store skill &key provenance)` writes `{name}/SKILL.md` (plus a `.provenance` sidecar). `git-skill-store` then `git add` + `git commit` (soft-uses `process-protocol:run` when `*process-backend*` is bound, else `uiop:run-program`). Provenance plist is in the commit body and the sidecar. `(rollback-skill store name version)` is `git checkout` of that file (or a numbered `SKILL.md.<n>` copy on `file-skill-store`). `(skill-versions store name)` → `skill-version` records (id, timestamp, provenance). Use `file-skill-store` when git is unavailable (`git-available-p`).

## License

MIT — see [LICENSE](LICENSE).
