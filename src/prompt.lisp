(in-package #:steer-protocol)

;;; Base system prompt (0.3): a short preamble plus guidance for the tools
;;; actually present. PROMPT-VARIANT-FOR picks a per-model variant from a
;;; model name, family keyword, backend, or variant instance.

(defclass prompt-variant ()
  ((name :initarg :name :reader prompt-variant-name :initform :default)
   (preamble :initarg :preamble :accessor prompt-variant-preamble
             :initform "You are a coding agent working in the user's project. Act through the tools you have, keep changes minimal, and verify them before you finish. Be concise."))
  (:documentation "Base system prompt shape. Subclass per model family."))

(defclass anthropic-prompt-variant (prompt-variant)
  ()
  (:default-initargs
   :name :anthropic
   :preamble "You are a coding agent working in the user's project. Use the tools to read before you edit, make the smallest change that works, and verify it. Answer concisely; do not narrate tool calls."))

(defclass openai-prompt-variant (prompt-variant)
  ()
  (:default-initargs
   :name :openai
   :preamble "You are a coding agent working in the user's project. Keep going until the task is done; use tools rather than guessing about files or code. Make focused changes and check them. Keep answers short."))

(defun prompt-variant-p (x)
  (typep x 'prompt-variant))

(defvar *tool-guidance* (make-hash-table :test #'equalp)
  "Tool name (case-insensitive) → one-line guidance string.")

(defun register-tool-guidance (names text)
  "Guidance TEXT for tool NAMES (a string or list of strings). → TEXT."
  (check-type text string)
  (dolist (name (if (listp names) names (list names)) text)
    (check-type name string)
    (setf (gethash name *tool-guidance*) text)))

(register-tool-guidance '("read" "read_file" "view")
                        "Read a file before you edit it; read only the ranges you need.")
(register-tool-guidance '("write" "write_file" "create_file")
                        "Write creates or overwrites whole files; prefer edit for changes.")
(register-tool-guidance '("edit" "edit_file" "str_replace" "apply_patch")
                        "Edit with exact, unique matches; re-read the file if an edit misses.")
(register-tool-guidance '("bash" "shell" "exec" "run_command")
                        "Run shell commands non-interactively; quote paths; tail long output.")
(register-tool-guidance '("grep" "search")
                        "Search content with grep before reading many files.")
(register-tool-guidance '("glob" "find" "ls" "list_files")
                        "Find files by name pattern instead of listing whole trees.")
(register-tool-guidance '("web_fetch" "fetch" "web_search")
                        "Fetch the web only when local sources do not answer the question.")
(register-tool-guidance '("todo" "todo_write")
                        "Track multi-step work in the todo list and keep it current.")

(defgeneric model-family (designator)
  (:documentation "Model family keyword (:ANTHROPIC, :OPENAI, …) for
   DESIGNATOR (model name, backend, keyword), or NIL.")
  (:method ((designator t)) nil)
  (:method ((designator symbol))
    (and designator (keywordp designator) designator))
  (:method ((designator string))
    (let ((s (string-downcase designator)))
      (flet ((prefix-p (p) (and (>= (length s) (length p))
                                (string= p s :end2 (length p)))))
        (cond
          ((or (prefix-p "claude") (prefix-p "anthropic")
               (search "anthropic." s))
           :anthropic)
          ((or (prefix-p "gpt") (prefix-p "o1") (prefix-p "o3") (prefix-p "o4")
               (prefix-p "codex") (prefix-p "openai"))
           :openai)
          (t nil)))))
  (:method ((designator llm-protocol:llm-backend))
    (or (let ((model (llm-protocol:backend-model designator)))
          (and model (model-family model)))
        (let ((cls (symbol-name (class-name (class-of designator)))))
          (cond ((search "ANTHROPIC" cls) :anthropic)
                ((search "OPENAI" cls) :openai)
                (t nil))))))

(defgeneric prompt-variant-for (designator)
  (:documentation "PROMPT-VARIANT for DESIGNATOR: a variant (itself), NIL
   (default), a family keyword, a model name, or an LLM-BACKEND. Add an EQL
   method on a family keyword for a new variant.")
  (:method ((designator prompt-variant)) designator)
  (:method ((designator t))
    (let ((family (model-family designator)))
      (if family
          (prompt-variant-for-family family)
          (make-instance 'prompt-variant)))))

(defgeneric prompt-variant-for-family (family)
  (:documentation "Variant for a family keyword. Unknown → base PROMPT-VARIANT.")
  (:method ((family t)) (make-instance 'prompt-variant))
  (:method ((family (eql :anthropic))) (make-instance 'anthropic-prompt-variant))
  (:method ((family (eql :openai))) (make-instance 'openai-prompt-variant)))

(defgeneric tool-guidance (variant tool-name)
  (:documentation "One-line guidance for TOOL-NAME under VARIANT, or NIL.
   Default: *TOOL-GUIDANCE*.")
  (:method ((variant prompt-variant) (tool-name string))
    (values (gethash tool-name *tool-guidance*))))

(defun %tool-name (tool)
  (etypecase tool
    (string tool)
    (symbol (string-downcase (symbol-name tool)))
    (llm-protocol:llm-tool (llm-protocol:llm-tool-name tool))))

(defgeneric render-system-prompt (variant preamble tool-lines extra)
  (:documentation "Assemble the prompt string. TOOL-LINES: (name . guidance).")
  (:method ((variant prompt-variant) preamble tool-lines extra)
    (with-output-to-string (o)
      (write-string preamble o)
      (when tool-lines
        (format o "~%~%# Tools~%~:{- ~a: ~a~%~}"
                (mapcar (lambda (l) (list (car l) (cdr l))) tool-lines)))
      (when (and extra (plusp (length extra)))
        (format o "~:[~%~;~]~%~a" tool-lines extra)))))

(defun build-system-prompt (&key tools model preamble extra)
  "Short base system prompt for MODEL (any PROMPT-VARIANT-FOR designator).
   Lists guidance only for TOOLS present (strings, symbols or LLM-TOOLs) that
   have guidance. PREAMBLE overrides the variant's; EXTRA is appended."
  (let* ((variant (prompt-variant-for model))
         (seen '())
         (lines (loop for tool in tools
                      for name = (%tool-name tool)
                      for text = (tool-guidance variant name)
                      when (and text (not (member text seen :test #'string=)))
                        collect (progn (push text seen) (cons name text)))))
    (string-right-trim '(#\Newline)
                       (render-system-prompt variant
                                             (or preamble (prompt-variant-preamble variant))
                                             lines extra))))
