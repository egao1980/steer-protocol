---
name: rove
description: >-
  Rove quick ref (ok / signals / deftest-parametrize). For policy and runner choice use cl-unit-testing.
---

# Rove

Upstream: [fukamachi/rove](https://github.com/fukamachi/rove).  
Stack pin (parametrize): [`egao1980/rove`](https://github.com/egao1980/rove) via [cl-stack-systems `imports/rove`](https://github.com/egao1980/cl-stack-systems).

**Full guidance (default runner, `deftest-parametrize`, pins, ASDF):** skill **[cl-unit-testing](../cl-unit-testing/SKILL.md)**.

## Quick ref

```lisp
(deftest example
  (ok (= 1 1))
  (ok (signals (error "x") 'simple-error)))

(deftest-parametrize add
    ((a b expected)
     (1 2 3)
     (0 0 0))
  (ok (= (+ a b) expected)))
```

Run: `(asdf:test-system :my-lib)` with a `my-lib/tests` system that `:depends-on ("rove")` and `(symbol-call :rove :run c)`.
