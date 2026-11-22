(in-package #:steer-protocol/tests)

;;; 0.4: frontmatter decoded by yaml-protocol (steer-protocol#5).
;;; Fixtures in tests/fixtures/ are copies of lisp-workspace's real
;;; skills/*/SKILL.md and rules/*.md.

(defun fixture (rel)
  (asdf:system-relative-pathname "steer-protocol"
                                 (concatenate 'string "tests/fixtures/" rel)))

(defun lines (&rest lines)
  (format nil "~{~a~%~}" lines))

(defun call-with-md-file (text fn)
  (uiop:with-temporary-file (:pathname p :stream s :prefix "fm" :type "md")
    (write-string text s)
    (finish-output s)
    (close s)
    (funcall fn p)))

(defmacro with-md-file ((var text) &body body)
  `(call-with-md-file ,text (lambda (,var) ,@body)))

;;; Real lisp-workspace skills: folded `description: >-`.

(deftest-parametrize workspace-skill-fixtures
    ((dir description body-start)
     :ids ("rove" "asdf" "team-solve" "spec-dsl" "cl-stack-conditions")
     ("rove"
      "Rove quick ref (ok / signals / deftest-parametrize). For policy and runner choice use cl-unit-testing."
      "# Rove")
     ("asdf"
      "ASDF 3: defsystem, new first-party .asd shape, load/test-system, source registry. Use when writing a new system, editing :depends-on / :cl-repo / :sources, \"component not found\", or CL_SOURCE_REGISTRY."
      "# ASDF")
     ("team-solve"
      "Use when implementing a cl-stack Common Lisp feature whose contract is a capability brief plus an existing ASDF test-op, or when the user runs /team-solve. Fresh agents, an on-disk ledger, and check-feature.sh is the verdict."
      "# team-solve")
     ("spec-dsl"
      "cl-stack formal-spec DSL: `spec-protocol` (`defspec` = CLOS protocol + spec AST, FSet runtime, ITF traces, MBT replay) + `spec-backend-quint` (emit .qnt, drive quint typecheck/run/test/verify/compile). Use when writing a `defspec`, adding contracts (:requires/:guard/:ensures), emitting Quint or TLA+ from Lisp, adding a spec backend, or wiring golden `.qnt` / ITF fixtures into Rove. Quint language itself: quint-modeling. Replay: spec-mbt-conformance."
      "# spec-dsl")
     ("cl-stack-conditions"
      "CLHS 9 conditions + restarts for first-party cl-stack. Use when defining errors, handler-bind / restart-case, or wrapping usocket/dexador/lparallel. No private error dialect."
      "# cl-stack conditions"))
  (let* ((path (fixture (format nil "skills/~a/SKILL.md" dir)))
         (skill (steer-protocol:load-skill path)))
    (ok (eq :skill (steer-protocol:steer-directive-kind skill)))
    (ok (equal dir (steer-protocol:steer-directive-name skill)))
    (ok (equal description (steer-protocol:steer-directive-description skill))
        "folded >- scalar is one line, not \">-\"")
    (ok (uiop:string-prefix-p body-start (steer-protocol:steer-directive-body skill)))
    (ok (equal path (steer-protocol:steer-directive-path skill)))
    (multiple-value-bind (fm present-p) (steer-protocol:skill-frontmatter skill)
      (ok present-p)
      (ok (equal dir (getf fm :name)))
      (ok (equal description (getf fm :description)))
      (ok (null (getf fm :description-continued))))
    (ok (null (steer-protocol:skill-paths skill)))))

;;; Real lisp-workspace rules: `paths:` block list, comments, Cursor keys.

(deftest-parametrize workspace-rule-fixtures
    ((file paths description-start)
     :ids ("cl-repo-asd" "cl-stack-conditions" "rules-and-logic")
     ("cl-repo-asd" '("**/*.asd") "New .asd — no :cl-repo unless overlays")
     ("cl-stack-conditions" '("**/*.lisp") "Idiomatic CL conditions")
     ("rules-and-logic" '("**/*.lisp") "Rule, policy and logical computation"))
  (let* ((path (fixture (format nil "rules/~a.md" file)))
         (rule (steer-protocol:load-skill path :kind :rule)))
    (ok (eq :rule (steer-protocol:steer-directive-kind rule)))
    (ok (equal file (steer-protocol:steer-directive-name rule)) "no name: the file name")
    (ok (equal paths (steer-protocol:skill-paths rule)) "block list, not \"\"")
    (ok (uiop:string-prefix-p description-start
                              (steer-protocol:steer-directive-description rule)))
    (ok (uiop:string-prefix-p "# " (steer-protocol:steer-directive-body rule)))
    (let ((fm (steer-protocol:skill-frontmatter rule)))
      (ok (equalp (coerce paths 'vector) (getf fm :paths)) "yaml-protocol's vector")
      (ok (equal (first paths) (getf fm :globs)) "quotes removed")
      (ok (null (getf fm :alwaysapply)) "false → NIL")
      (ok (null (getf fm :|# CURSOR|)) "comments are not keys")
      (ok (= 8 (length fm)) "description, paths, globs, alwaysApply only"))))

;;; YAML forms.

(deftest frontmatter-yaml-forms
  (multiple-value-bind (fm body tools present-p)
      (steer-protocol:parse-skill-markdown
       (lines "---"
              "# a comment: not a key"
              "name: \"pdf\""
              "description: 'Read PDFs: text, tables'"
              "literal: |"
              "  one"
              "  two"
              "flow: [a, \"b c\"]"
              "block:"
              "  - x"
              "  - y"
              "count: 3"
              "on: true"
              "empty:"
              "allowed_tools: Read"
              "metadata:"
              "  author: someone"
              "---"
              ""
              "Body."))
    (ok present-p)
    (ok (equal "Body." body))
    (ok (null tools))
    (ok (equal "pdf" (getf fm :name)) "quotes removed")
    (ok (equal "Read PDFs: text, tables" (getf fm :description)) "colon kept")
    (ok (equal (format nil "one~%two~%") (getf fm :literal)))
    (ok (equalp #("a" "b c") (getf fm :flow)))
    (ok (equalp #("x" "y") (getf fm :block)))
    (ok (eql 3 (getf fm :count)))
    (ok (eq t (getf fm :on)))
    (ok (null (getf fm :empty)))
    (ok (equal "Read" (getf fm :allowed-tools)) "_ → -")
    (ok (equal "someone" (gethash "author" (getf fm :metadata))))
    (ok (null (getf fm :|# A COMMENT|)))))

(deftest frontmatter-crlf-and-empty
  (multiple-value-bind (fm body tools present-p)
      (steer-protocol:parse-skill-markdown
       (format nil "---~c~%name: w~c~%paths:~c~%  - \"a/*.md\"~c~%---~c~%Win.~c~%"
               #\Return #\Return #\Return #\Return #\Return #\Return))
    (declare (ignore tools))
    (ok present-p)
    (ok (equal "w" (getf fm :name)))
    (ok (equalp #("a/*.md") (getf fm :paths)))
    (ok (equal "Win." body)))
  (multiple-value-bind (fm body tools present-p)
      (steer-protocol:parse-skill-markdown (lines "---" "---" "Only body."))
    (declare (ignore tools))
    (ok present-p "an empty block is still frontmatter")
    (ok (null fm))
    (ok (equal "Only body." body))))

(deftest frontmatter-tools-list
  (multiple-value-bind (fm body tools)
      (steer-protocol:parse-skill-markdown
       (lines "---" "name: t" "tools:" "  - lookup" "  - name: grep"
              "    description: Search" "---" "x"))
    (declare (ignore fm body))
    (ok (equal '("lookup" "grep") (mapcar #'llm-protocol:llm-tool-name tools)))
    (ok (equal "Search" (llm-protocol:llm-tool-description (second tools))))))

;;; No frontmatter.

(deftest no-frontmatter
  (multiple-value-bind (fm body tools present-p)
      (steer-protocol:parse-skill-markdown (lines "" "# Title" "" "Text: with colon."))
    (declare (ignore tools))
    (ok (null fm))
    (ok (null present-p))
    (ok (equal (format nil "# Title~%~%Text: with colon.") body)))
  (with-md-file (p (lines "Just text." "key: not frontmatter"))
    (let ((d (steer-protocol:load-skill p :kind :rule)))
      (ok (equal (pathname-name p) (steer-protocol:steer-directive-name d)))
      (ok (null (steer-protocol:steer-directive-description d)))
      (ok (equal (format nil "Just text.~%key: not frontmatter")
                 (steer-protocol:steer-directive-body d)))
      (ok (null (steer-protocol:skill-paths d)))
      (multiple-value-bind (fm present-p) (steer-protocol:skill-frontmatter d)
        (ok (null fm))
        (ok (null present-p))))))

(deftest frontmatter-name-missing-or-not-string
  (with-md-file (p (lines "---" "description: d" "---" "b"))
    (let ((d (steer-protocol:load-skill p)))
      (ok (equal (pathname-name p) (steer-protocol:steer-directive-name d)))
      (ok (null (getf (steer-protocol:skill-frontmatter d) :name))
          "callers can tell the name was missing")))
  (with-md-file (p (lines "---" "name: 42" "description: 7" "---" "b"))
    (let ((d (steer-protocol:load-skill p)))
      (ok (equal (pathname-name p) (steer-protocol:steer-directive-name d)))
      (ok (null (steer-protocol:steer-directive-description d)))
      (ok (eql 42 (getf (steer-protocol:skill-frontmatter d) :name))))))

;;; Bad frontmatter.

(deftest-parametrize bad-frontmatter-signals
    ((text)
     :ids ("unclosed" "bad-yaml" "not-a-mapping" "a-list")
     ((lines "---" "name: x" "description: y"))
     ((lines "---" "name: [broken" "description: x" "---" "b"))
     ((lines "---" "just a scalar" "---" "b"))
     ((lines "---" "- a" "- b" "---" "b")))
  (ok (signals (steer-protocol:parse-skill-markdown text)
               'steer-protocol:steer-frontmatter-error))
  (ok (signals (steer-protocol:parse-skill-markdown text)
               'steer-protocol:steer-error)
      "a steer-error subclass")
  (with-md-file (p text)
    (let ((c (handler-case (progn (steer-protocol:load-skill p) nil)
               (steer-protocol:steer-frontmatter-error (e) e))))
      (ok c)
      (when c
        (ok (equal p (steer-protocol:steer-frontmatter-error-path c)))
        (ok (search "bad frontmatter" (princ-to-string c)))
        (ok (search (uiop:native-namestring p) (princ-to-string c)))))))

(deftest bad-yaml-cause-is-yaml-condition
  (let ((c (handler-case
               (progn (steer-protocol:parse-skill-markdown
                       (lines "---" "name: [broken" "---" "b"))
                      nil)
             (steer-protocol:steer-frontmatter-error (e) e))))
    (ok (typep (steer-protocol:steer-frontmatter-error-cause c)
               'yaml-protocol:yaml-error))))

(deftest bad-frontmatter-use-value
  (with-md-file (p (lines "---" "name: [broken" "---" "b"))
    (let ((fallback (steer-protocol:make-steer-skill "fallback")))
      (ok (eq fallback
              (handler-bind ((steer-protocol:steer-frontmatter-error
                               (lambda (c)
                                 (declare (ignore c))
                                 (invoke-restart 'use-value fallback))))
                (steer-protocol:load-skill p)))))))

(deftest-parametrize skill-paths-forms
    ((yaml expected)
     :ids ("comma-string" "flow-list" "empty-list" "absent")
     ("paths: \"src/**/*.ts, , lib/*.js\"" '("src/**/*.ts" "lib/*.js"))
     ("paths: [\"**/*.lisp\", \"*.asd\"]" '("**/*.lisp" "*.asd"))
     ("paths: []" nil)
     ("other: 1" nil))
  (with-md-file (p (lines "---" yaml "---" "r"))
    (ok (equal expected (steer-protocol:skill-paths
                         (steer-protocol:load-skill p :kind :rule))))))

(deftest-parametrize skill-paths-bad
    ((yaml)
     :ids ("number" "mixed-list")
     ("paths: 3")
     ((format nil "paths:~%  - a~%  - 2")))
  (with-md-file (p (lines "---" yaml "---" "r"))
    (let ((rule (steer-protocol:load-skill p :kind :rule)))
      (ok (signals (steer-protocol:skill-paths rule)
                   'steer-protocol:steer-frontmatter-error)))))

;;; Round trip through SERIALIZE-SKILL-MARKDOWN.

(deftest serialize-round-trip-yaml
  (let* ((skill (steer-protocol:make-steer-skill
                 "pdf"
                 :description "Read PDFs: text, tables"
                 :body "Body."
                 :extra (list :license "MIT" :paths (vector "**/*.pdf"))))
         (text (steer-protocol:serialize-skill-markdown skill)))
    (multiple-value-bind (fm body) (steer-protocol:parse-skill-markdown text)
      (ok (equal "pdf" (getf fm :name)))
      (ok (equal "Read PDFs: text, tables" (getf fm :description)))
      (ok (equal "MIT" (getf fm :license)))
      (ok (equalp #("**/*.pdf") (getf fm :paths)))
      (ok (equal "Body." body))))
  (let* ((loaded (steer-protocol:load-skill (fixture "skills/asdf/SKILL.md")))
         (again (steer-protocol:parse-skill-markdown
                 (steer-protocol:serialize-skill-markdown loaded))))
    (ok (equal (steer-protocol:steer-directive-description loaded)
               (getf again :description)))))
