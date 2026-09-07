(in-package #:steer-protocol)

;;; Cursor/Codex SKILL.md: YAML frontmatter + body. Not A2A agent-skill.

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

(defun parse-skill-markdown (text)
  "→ (values plist body). No frontmatter → (values nil text)."
  (check-type text string)
  (let ((raw text)
        (start 0))
    (loop while (and (< start (length raw))
                     (member (char raw start) '(#\Newline #\Return #\Space #\Tab)))
          do (incf start))
    (let ((s (subseq raw start)))
      (cond
        ((or (< (length s) 3) (not (string= (subseq s 0 3) "---")))
         (values nil (string-trim '(#\Space #\Tab #\Newline #\Return) s)))
        (t
         (let* ((after (subseq s 3))
                (nl (or (position #\Newline after) 0))
                (rest (subseq after (1+ nl)))
                (end (search (format nil "~%---") rest)))
           (unless end
             (error 'steer-error :message "unclosed SKILL.md frontmatter"))
           (values (%parse-frontmatter-lines (subseq rest 0 end))
                   (string-trim '(#\Space #\Tab #\Newline #\Return)
                                (subseq rest (+ end 4))))))))))

(defun load-skill (path &key (kind :skill))
  "Read PATH as SKILL.md (or a rule file). Missing → STEER-SKILL-NOT-FOUND
   (USE-VALUE)."
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
    (multiple-value-bind (fm body)
        (parse-skill-markdown (uiop:read-file-string p))
      (make-steer-directive
       :kind kind
       :name (or (getf fm :name) (pathname-name p))
       :description (getf fm :description)
       :body body
       :path p
       :extra fm))))

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
