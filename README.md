# steer-protocol

Lispy **CLOS** rules / skills for [cl-stack](https://github.com/egao1980/cl-stack). One directive type, `:kind` `:rule` or `:skill`.

**Not** A2A `agent-skill` (card advertisement). **Not** GFs on `llm-protocol`. **Not** RAG.

| System | Role | Repo |
|--------|------|------|
| `steer-protocol` (`stack-steer`) | Protocol + in-memory source + `SKILL.md` loader | this repo |

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
| files | `parse-skill-markdown` / `load-skill` / `load-skills-from-directory` | Cursor/Codex `SKILL.md` frontmatter |

Wire an agent with `:steering` (`ai-agent-protocol` **0.2.2**). `prepare-agent-turns` applies after memory recall.

Missing source → `steer-missing-source` (`use-value`). Unknown name → `steer-unknown-directive` (`use-value` / `continue`). Missing file → `steer-skill-not-found` (`use-value`).

## License

MIT — see [LICENSE](LICENSE).
