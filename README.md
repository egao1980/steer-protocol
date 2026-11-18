# steer-protocol

Lispy **CLOS** rules / skills for [cl-stack](https://github.com/egao1980/cl-stack). One directive type, `:kind` `:rule` or `:skill`. **0.2** adds tool-bearing skills and a versioned skill store. **0.3** adds lazily discovered, path-scoped instructions (`AGENTS.md` found as the agent reaches files) and a small per-model base system prompt builder.

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
| instructions | `discover-instructions` / `forget-instructions` / `instruction-candidates` | `instruction-discovery` |
| base prompt | `build-system-prompt` / `prompt-variant-for` / `tool-guidance` | `prompt-variant`, `anthropic-prompt-variant`, `openai-prompt-variant` |
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

## Path-scoped instructions (0.3)

Modelled on "instructions found as the agent reaches them". An `instruction-discovery` is a `steering-source` rooted at a project directory:

```lisp
(defvar *disc* (stack-steer:make-instruction-discovery #p"/work/proj/"
                                                       :include-claude t))

;; The agent just read src/net/http.lisp:
(stack-steer:discover-instructions *disc* "src/net/http.lisp")
;; → (#<directive "AGENTS.md"> #<directive "src/net/AGENTS.md">), outermost first.
(stack-steer:discover-instructions *disc* "src/net/tls.lisp")   ; → NIL (already in context)

(stack-steer:compile-instructions directives) ; → <instructions path=… scope=…> blocks for a turn
(stack-steer:forget-instructions *disc*)      ; after a compaction: re-inject on next discovery
```

- Walks from the file's directory up to the root (root included unless `:include-root nil`). Paths outside the root find nothing.
- `:names` (default `*default-instruction-names*` = `("AGENTS.md")`), `:include-claude t` appends `CLAUDE.md`. `:per-directory :first` (default) takes the first name found per directory; `:all` takes each.
- Directives are `:rule`s named by their root-relative path; `extra` carries `:scope` (directory), `:scope-name` and `:hash`.
- De-duplication: `list-directives` = what was injected and is still in context. `forget-instructions` (all, or `:path`) resets after a compaction. `instruction-injected-p` asks about one file. `:mark nil` peeks; `mark-instructions-injected` records later.
- Change detection: `instruction-content-hash` (GF; default FNV-1a 64, not a security hash). A changed file is returned again and replaces the stored version.
- `coerce-instruction-discovery` takes a discovery, a root path or a plist `(:root dir :include-claude t …)`. `copy-instruction-discovery` gives a fresh copy (same class and config, empty memory unless `:keep-injected`) — one per agent run.
- Unreadable file → `steer-instruction-unreadable` (`:cause`) with `use-value` (text) / `continue` (skip).

## Base system prompt (0.3)

```lisp
(stack-steer:build-system-prompt :tools (list read-tool bash-tool) :model "claude-opus-5-5")
```

A short preamble plus one guidance line per tool **actually present** (strings, symbols or `llm-tool`s). Tools without guidance are not mentioned. `register-tool-guidance` adds lines to `*tool-guidance*`.

Variants are CLOS: `prompt-variant-for` takes a variant, `nil`, a family keyword, a model name or an `llm-backend`; `model-family` maps names (`claude*` → `:anthropic`, `gpt*`/`o3*` → `:openai`); `prompt-variant-for-family` is the `eql`-dispatched hook for a new variant. Specialize `tool-guidance` or `render-system-prompt` on your variant class to change wording or layout.

## License

MIT — see [LICENSE](LICENSE).
