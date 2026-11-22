(in-package #:steer-protocol)

;;; Agent Skills / Cursor / Codex SKILL.md and Claude Code rule files:
;;; YAML frontmatter + Markdown body. Not A2A agent-skill.
;;;
;;; Frontmatter (0.4): the lines between an opening `---` line (the first
;;; non-blank line) and the next `---` line, decoded by yaml-protocol
;;; (YAML 1.2, Core schema). It must be a mapping (or empty). The plist has
;;; keyword keys (`_` → `-`, upcased: `allowed_tools` → :ALLOWED-TOOLS) and
;;; yaml-protocol's values: strings (folded `>-` / literal `|` scalars
;;; included), vectors (block or flow lists), T / NIL, numbers, hash-tables
;;; (nested mappings). A top-level null (`key:` with no value) is NIL.
;;; Unclosed, unparsable or non-mapping frontmatter → STEER-FRONTMATTER-ERROR.
;;;
;;; Tool-bearing skills (0.2):
;;;   Frontmatter:  tools: lookup, grep        (or a YAML list of names, or
;;;                                             of {name, description, parameters})
;;;   Body section: ## tools
;;;                 ### lookup
;;;                 description: Look up a symbol
;;;                 name: lookup
;;; Each `### name` block is decoded as a YAML mapping too; a block that is
;;; not one gives a tool with just the heading's name.
;;;
;;; Descriptors are llm-protocol:llm-tool (name / description / parameters).
;;; Implementations live on EXTRA as :tool-fns (alist) or a :tools plist of
;;; name → function/symbol — see REGISTER-SKILL-TOOL-FN / SKILL-TOOL-FN.

(defun %frontmatter-key (key)
  (intern (string-upcase (substitute #\- #\_ (if (stringp key)
                                                  key
                                                  (princ-to-string key))))
          :keyword))

(defun %frontmatter-plist (table)
  "Hash-table (string keys) → plist, keys as %FRONTMATTER-KEY, top-level
   :NULL → NIL."
  (let ((out '()))
    (maphash (lambda (k v)
               (push (%frontmatter-key k) out)
               (push (if (eq v :null) nil v) out))
             table)
    (nreverse out)))

(defun %decode-frontmatter (text &optional path)
  "Decode the YAML TEXT between the `---` lines → plist."
  (let ((value (handler-case (yaml-protocol:decode text)
                 (error (e)
                   (error 'steer-frontmatter-error
                          :path path :cause e
                          :message (format nil "~a" e))))))
    (cond
      ((eq value :null) nil)
      ((hash-table-p value) (%frontmatter-plist value))
      (t (error 'steer-frontmatter-error
                :path path
                :message (format nil "frontmatter is not a mapping: ~s"
                                 value))))))

(defun %yaml-mapping-or-nil (text)
  "TEXT as a YAML mapping plist, or NIL when it is not one (tool blocks)."
  (let ((value (ignore-errors (yaml-protocol:decode text))))
    (and (hash-table-p value) (%frontmatter-plist value))))

(defun %split-csv (s)
  (remove-if (lambda (p) (zerop (length p)))
             (mapcar (lambda (p) (string-trim '(#\Space #\Tab) p))
                     (uiop:split-string s :separator '(#\,)))))

(defun %markdown-heading (line)
  "→ (values level title) or NIL."
  (let ((line (string-trim '(#\Return #\Space #\Tab) line)))
    (when (and (plusp (length line)) (char= (char line 0) #\#))
      (let ((n 0))
        (loop while (and (< n (length line)) (char= (char line n) #\#))
              do (incf n))
        (when (plusp n)
          (values n (string-trim '(#\Space #\Tab #\/) (subseq line n))))))))

(defun %make-named-tool (name &optional description parameters)
  (llm-protocol:make-llm-tool
   :name name
   :description (and (stringp description) (plusp (length description))
                     description)
   :parameters (cond ((stringp parameters)
                      (and (plusp (length parameters)) parameters))
                     (t parameters))))

(defun %tool-from-spec (spec)
  "A tool name string, an llm-tool, or a mapping {name, description,
   parameters} → llm-tool, or NIL."
  (cond
    ((llm-protocol:llm-tool-p spec) spec)
    ((and (stringp spec) (plusp (length spec))) (%make-named-tool spec))
    ((hash-table-p spec)
     (let ((name (gethash "name" spec)))
       (when (and (stringp name) (plusp (length name)))
         (%make-named-tool name (gethash "description" spec)
                           (or (gethash "parameters" spec)
                               (gethash "input_schema" spec))))))
    (t nil)))

(defun %tools-from-frontmatter-field (field)
  (cond
    ((null field) nil)
    ((stringp field)
     (mapcar #'%make-named-tool (%split-csv field)))
    ((or (listp field) (and (vectorp field) (not (stringp field))))
     (remove nil (map 'list #'%tool-from-spec field)))
    (t nil)))

(defun %parse-tool-entry (heading-name block)
  (let ((fm (%yaml-mapping-or-nil block)))
    (%make-named-tool (let ((n (getf fm :name)))
                        (if (and (stringp n) (plusp (length n))) n heading-name))
                      (getf fm :description)
                      (let ((p (or (getf fm :parameters) (getf fm :input-schema))))
                        (and (not (eq p :null)) p)))))

(defun %parse-tools-section (body)
  "Collect `### name` entries under the first `## tools` heading."
  (unless (and body (plusp (length body)))
    (return-from %parse-tools-section nil))
  (let ((lines (uiop:split-string body :separator '(#\Newline)))
        (in-tools nil)
        (current-name nil)
        (current-lines '())
        (out '()))
    (labels ((flush ()
               (when current-name
                 (push (%parse-tool-entry
                        current-name
                        (format nil "~{~a~^~%~}"
                                (mapcar (lambda (l) (string-right-trim '(#\Return) l))
                                        (nreverse current-lines))))
                       out)
                 (setf current-name nil current-lines '()))))
      (dolist (raw lines)
        (multiple-value-bind (level title) (%markdown-heading raw)
          (cond
            ((and level (= level 2) (string-equal title "tools"))
             (flush)
             (setf in-tools t))
            ((and in-tools level (<= level 2))
             (flush)
             (setf in-tools nil))
            ((and in-tools level (= level 3) (plusp (length title)))
             (flush)
             (setf current-name title))
            ((and in-tools current-name)
             (push raw current-lines)))))
      (flush))
    (nreverse out)))

(defun %merge-tools (base overlay)
  "BASE then OVERLAY; overlay replaces a base tool of the same name."
  (let ((out (copy-list base)))
    (dolist (tool overlay)
      (let ((name (llm-protocol:llm-tool-name tool)))
        (setf out (remove name out :key #'llm-protocol:llm-tool-name
                          :test #'equal))
        (setf out (append out (list tool)))))
    out))

(defun %collect-skill-tools (tools-field body)
  (%merge-tools (%tools-from-frontmatter-field tools-field)
                (%parse-tools-section body)))

(defun %fence-line-p (line)
  (string= "---" (string-right-trim '(#\Return #\Space #\Tab) line)))

(defun %join-lines (lines)
  (format nil "~{~a~^~%~}"
          (mapcar (lambda (l) (string-right-trim '(#\Return) l)) lines)))

(defun %split-frontmatter (text &optional path)
  "→ (values yaml-text-or-nil body). NIL when TEXT has no frontmatter.
   An opening `---` with no closing `---` line → STEER-FRONTMATTER-ERROR."
  (let* ((start (or (position-if-not
                     (lambda (c) (member c '(#\Newline #\Return #\Space #\Tab)))
                     text)
                    (length text)))
         (lines (uiop:split-string (subseq text start) :separator '(#\Newline))))
    (if (not (and lines (%fence-line-p (first lines))))
        (values nil (string-trim '(#\Space #\Tab #\Newline #\Return)
                                 (subseq text start)))
        (let ((end (position-if #'%fence-line-p lines :start 1)))
          (unless end
            (error 'steer-frontmatter-error
                   :path path
                   :message "unclosed frontmatter (no closing --- line)"))
          (values (%join-lines (subseq lines 1 end))
                  (string-trim '(#\Space #\Tab #\Newline #\Return)
                               (%join-lines (subseq lines (1+ end)))))))))

(defun %parse-skill-markdown (text path)
  (check-type text string)
  (multiple-value-bind (yaml body) (%split-frontmatter text path)
    (let ((fm (and yaml (%decode-frontmatter yaml path))))
      (values fm body (%collect-skill-tools (getf fm :tools) body)
              (and yaml t)))))

(defun parse-skill-markdown (text)
  "→ (values plist body tools frontmatter-p). No frontmatter →
   (values nil text tools nil). TOOLS is a list of llm-protocol:llm-tool,
   or NIL. Bad frontmatter → STEER-FRONTMATTER-ERROR."
  (%parse-skill-markdown text nil))

(defun %extra-with-tools (fm tools &optional (frontmatter-p (and fm t)))
  "EXTRA: :frontmatter-p, :frontmatter (the plist), :skill-tools when
   TOOLS, then the frontmatter keys themselves (0.3 shape)."
  (append (list :frontmatter-p frontmatter-p :frontmatter fm)
          (and tools (list :skill-tools tools))
          fm))

(defun %directive-from-markdown (fm body tools frontmatter-p
                                 &key kind default-name path)
  (let ((name (getf fm :name))
        (description (getf fm :description)))
    (make-steer-directive
     :kind kind
     :name (if (and (stringp name) (plusp (length name))) name default-name)
     :description (and (stringp description) description)
     :body body
     :path path
     :extra (%extra-with-tools fm tools frontmatter-p))))

(defun load-skill (path &key (kind :skill))
  "Read PATH as SKILL.md (or a rule file, KIND :rule) → STEER-DIRECTIVE.
   NAME is the frontmatter's `name` (a string), else the file name;
   DESCRIPTION the frontmatter's `description` when it is a string; BODY the
   text after the frontmatter (all of it without one), trimmed; PATH the
   pathname. EXTRA holds the whole frontmatter (SKILL-FRONTMATTER), its keys
   and :skill-tools. Missing → STEER-SKILL-NOT-FOUND; bad frontmatter →
   STEER-FRONTMATTER-ERROR; both with USE-VALUE (return a supplied value)."
  (let ((p (pathname path)))
    (restart-case
        (progn
          (unless (probe-file p)
            (error 'steer-skill-not-found
                   :path p
                   :message (format nil "no file ~s" p)))
          (multiple-value-bind (fm body tools frontmatter-p)
              (%parse-skill-markdown (uiop:read-file-string p) p)
            (%directive-from-markdown fm body tools frontmatter-p
                                      :kind kind
                                      :default-name (pathname-name p)
                                      :path p)))
      (use-value (value)
        :report "Use a supplied directive"
        value))))

(defun skill-frontmatter (directive)
  "→ (values plist frontmatter-p): the decoded frontmatter of a directive
   made by LOAD-SKILL (keyword keys, yaml-protocol values) and whether the
   file had a frontmatter block at all."
  (check-type directive steer-directive)
  (let ((extra (steer-directive-extra directive)))
    (values (getf extra :frontmatter)
            (and (getf extra :frontmatter-p) t))))

(defun skill-paths (directive)
  "→ list of glob strings from the frontmatter's `paths` (Claude Code rules):
   a YAML list of strings, or one comma-separated string (pieces trimmed,
   empty ones dropped). Absent or empty → NIL. Anything else →
   STEER-FRONTMATTER-ERROR."
  (check-type directive steer-directive)
  (let ((paths (getf (skill-frontmatter directive) :paths)))
    (cond
      ((null paths) nil)
      ((stringp paths) (%split-csv paths))
      ((and (vectorp paths) (every #'stringp paths))
       (remove "" (coerce paths 'list) :test #'string=))
      (t (error 'steer-frontmatter-error
                :path (steer-directive-path directive)
                :message (format nil "paths must be a list of strings or a comma-separated string, not ~s"
                                 paths))))))

(defun skill-tools (skill)
  "→ list of llm-protocol:llm-tool descriptors on SKILL."
  (check-type skill steer-directive)
  (let ((extra (steer-directive-extra skill)))
    (or (copy-list (getf extra :skill-tools))
        (%collect-skill-tools (getf extra :tools)
                              (steer-directive-body skill)))))

(defun %implementation-plist-p (x)
  (and (consp x)
       (evenp (length x))
       (loop for (k v) on x by #'cddr
             always (and (or (stringp k) (symbolp k))
                         (or (functionp v)
                             (and (symbolp v) (not (keywordp v))))))))

(defun %plist-get-equal (plist key)
  (loop for (k v) on plist by #'cddr
        when (and k (string-equal (string k) (string key)))
          return v))

(defun skill-tool-fn (skill name)
  "Implementation function or symbol for NAME, or NIL.
   Looks at EXTRA :tool-fns (alist) then a :tools implementation plist."
  (check-type skill steer-directive)
  (check-type name string)
  (let ((extra (steer-directive-extra skill)))
    (or (cdr (assoc name (getf extra :tool-fns) :test #'string-equal))
        (let ((tools (getf extra :tools)))
          (when (%implementation-plist-p tools)
            (%plist-get-equal tools name))))))

(defun register-skill-tool-fn (skill name fn)
  "Record FN (function or symbol) for NAME on SKILL's EXTRA :tool-fns."
  (check-type skill steer-directive)
  (check-type name string)
  (let* ((extra (copy-list (steer-directive-extra skill)))
         (fns (acons name fn
                     (remove name (copy-alist (getf extra :tool-fns))
                             :key #'car :test #'equal))))
    (if (getf extra :tool-fns)
        (setf (getf extra :tool-fns) fns)
        (setf extra (list* :tool-fns fns extra)))
    (setf (steer-directive-extra skill) extra)
    fn))


(defparameter *serialize-skip-keys*
  '(:name :description :tools :skill-tools :tool-fns :frontmatter :frontmatter-p)
  "EXTRA keys SERIALIZE-SKILL-MARKDOWN does not write as frontmatter keys.")

(defun %serializable-value-p (v)
  (or (stringp v) (numberp v) (eq v t) (hash-table-p v)
      (and (vectorp v) (not (stringp v)))))

(defun serialize-skill-markdown (skill)
  "SKILL.md text: YAML frontmatter (encoded by yaml-protocol, so
   LOAD-SKILL reads it back) + body. Tools listed as `tools:` names when
   SKILL-TOOLS is non-empty; a `## tools` body section is left as-is. Other
   EXTRA keywords with string, number, T, list (vector) or mapping values
   are written with downcased names."
  (check-type skill steer-directive)
  (let ((table (make-hash-table :test #'equal)))
    (setf (gethash "name" table) (steer-directive-name skill))
    (let ((d (steer-directive-description skill)))
      (when (and (stringp d) (plusp (length d)))
        (setf (gethash "description" table) d)))
    (let ((tools (skill-tools skill)))
      (when tools
        (setf (gethash "tools" table)
              (format nil "~{~a~^, ~}" (mapcar #'llm-protocol:llm-tool-name tools)))))
    (let ((extra (steer-directive-extra skill)))
      (loop for (k v) on extra by #'cddr
            for key = (and (keywordp k) (string-downcase (symbol-name k)))
            when (and key
                      (not (member k *serialize-skip-keys*))
                      (%serializable-value-p v)
                      (not (nth-value 1 (gethash key table))))
              do (setf (gethash key table) v)))
    (with-output-to-string (o)
      (format o "---~%")
      (let ((yaml (string-right-trim '(#\Newline #\Return)
                                     (yaml-protocol:encode table))))
        (format o "~a~%" yaml))
      (format o "---~%")
      (let ((body (steer-directive-body skill)))
        (when (and body (plusp (length body)))
          (format o "~%~a~%" body))))))

(defun %skill-files (root)
  (let ((root (uiop:ensure-directory-pathname root))
        (out '()))
    (uiop:collect-sub*directories
     root (constantly t) (constantly t)
     (lambda (dir)
       (let ((f (merge-pathnames "SKILL.md" dir)))
         (when (probe-file f)
           (push f out)))))
    (nreverse out)))

(defun load-skills-from-directory (root)
  "Every SKILL.md under ROOT, depth-first."
  (let ((root (uiop:ensure-directory-pathname root)))
    (unless (uiop:directory-exists-p root)
      (return-from load-skills-from-directory
        (restart-case
            (error 'steer-skill-not-found
                   :path root
                   :message (format nil "no directory ~s" root))
          (use-value (value)
            :report "Use a supplied directive list"
            value)
          (continue ()
            :report "Treat as empty"
            nil))))
    (mapcar #'load-skill (%skill-files root))))
