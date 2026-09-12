(in-package #:steer-protocol)

;;; Cursor/Codex SKILL.md: YAML frontmatter + body. Not A2A agent-skill.
;;;
;;; Tool-bearing skills (0.2):
;;;   Frontmatter:  tools: lookup, grep
;;;   Body section: ## tools
;;;                 ### lookup
;;;                 description: Look up a symbol
;;;                 name: lookup
;;;
;;; Descriptors are llm-protocol:llm-tool (name / description / parameters).
;;; Implementations live on EXTRA as :tool-fns (alist) or a :tools plist of
;;; name → function/symbol — see REGISTER-SKILL-TOOL-FN / SKILL-TOOL-FN.

(defun %parse-frontmatter-lines (fm)
  (let ((out '()))
    (dolist (line (uiop:split-string fm :separator '(#\Newline)))
      (let ((line (string-trim '(#\Return #\Space #\Tab) line)))
        (when (plusp (length line))
          (let ((colon (position #\: line)))
            (when colon
              (let ((k (intern (string-upcase
                                (substitute #\- #\_
                                            (string-trim '(#\Space)
                                                         (subseq line 0 colon))))
                               :keyword))
                    (v (string-trim '(#\Space #\Tab) (subseq line (1+ colon)))))
                (setf out (list* k v out))))))))
    out))

(defun %split-csv (s)
  (remove-if (lambda (p) (zerop (length p)))
             (mapcar (lambda (p)
                       (string-trim '(#\Space #\Tab #\[ #\] #\" #\') p))
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
   :description (and description (plusp (length description)) description)
   :parameters (and parameters (plusp (length (string parameters)))
                    parameters)))

(defun %tools-from-frontmatter-field (field)
  (cond
    ((null field) nil)
    ((stringp field)
     (mapcar #'%make-named-tool (%split-csv field)))
    ((and (listp field) (every #'llm-protocol:llm-tool-p field))
     (copy-list field))
    ((and (listp field) (every #'stringp field))
     (mapcar #'%make-named-tool field))
    (t nil)))

(defun %parse-tool-entry (heading-name block)
  (let ((fm (%parse-frontmatter-lines block)))
    (%make-named-tool (or (getf fm :name) heading-name)
                      (getf fm :description)
                      (or (getf fm :parameters) (getf fm :input-schema)))))

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
                        (format nil "~{~a~^~%~}" (nreverse current-lines)))
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

(defun parse-skill-markdown (text)
  "→ (values plist body tools). No frontmatter → (values nil text tools).
   TOOLS is a list of llm-protocol:llm-tool, or NIL."
  (check-type text string)
  (let ((raw text)
        (start 0))
    (loop while (and (< start (length raw))
                     (member (char raw start) '(#\Newline #\Return #\Space #\Tab)))
          do (incf start))
    (let ((s (subseq raw start)))
      (cond
        ((or (< (length s) 3) (not (string= (subseq s 0 3) "---")))
         (let ((body (string-trim '(#\Space #\Tab #\Newline #\Return) s)))
           (values nil body (%collect-skill-tools nil body))))
        (t
         (let* ((after (subseq s 3))
                (nl (or (position #\Newline after) 0))
                (rest (subseq after (1+ nl)))
                (end (search (format nil "~%---") rest)))
           (unless end
             (error 'steer-error :message "unclosed SKILL.md frontmatter"))
           (let ((fm (%parse-frontmatter-lines (subseq rest 0 end)))
                 (body (string-trim '(#\Space #\Tab #\Newline #\Return)
                                    (subseq rest (+ end 4)))))
             (values fm body (%collect-skill-tools (getf fm :tools) body)))))))))

(defun %extra-with-tools (fm tools)
  (if tools
      (list* :skill-tools tools fm)
      fm))

(defun load-skill (path &key (kind :skill))
  "Read PATH as SKILL.md (or a rule file). Missing → STEER-SKILL-NOT-FOUND
   (USE-VALUE). Parsed tool descriptors are on EXTRA as :skill-tools."
  (let ((p (pathname path)))
    (unless (probe-file p)
      (return-from load-skill
        (restart-case
            (error 'steer-skill-not-found
                   :path p
                   :message (format nil "no file ~s" p))
          (use-value (value)
            :report "Use a supplied directive"
            value))))
    (multiple-value-bind (fm body tools)
        (parse-skill-markdown (uiop:read-file-string p))
      (make-steer-directive
       :kind kind
       :name (or (getf fm :name) (pathname-name p))
       :description (getf fm :description)
       :body body
       :path p
       :extra (%extra-with-tools fm tools)))))

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

(defun serialize-skill-markdown (skill)
  "SKILL.md text: YAML-ish frontmatter + body. Tools listed as `tools:` names
   when SKILL-TOOLS is non-empty; a `## tools` body section is left as-is."
  (check-type skill steer-directive)
  (with-output-to-string (o)
    (format o "---~%")
    (format o "name: ~a~%" (steer-directive-name skill))
    (when (and (steer-directive-description skill)
               (plusp (length (steer-directive-description skill))))
      (format o "description: ~a~%" (steer-directive-description skill)))
    (let ((tools (skill-tools skill)))
      (when tools
        (format o "tools: ~{~a~^, ~}~%"
                (mapcar #'llm-protocol:llm-tool-name tools))))
    (let ((extra (steer-directive-extra skill)))
      (loop for (k v) on extra by #'cddr
            unless (or (member k '(:name :description :tools :skill-tools
                                   :tool-fns))
                       (not (keywordp k))
                       (not (or (stringp v) (numberp v))))
              do (format o "~a: ~a~%"
                         (string-downcase (symbol-name k))
                         v)))
    (format o "---~%")
    (let ((body (steer-directive-body skill)))
      (when (and body (plusp (length body)))
        (format o "~%~a~%" body)))))

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
