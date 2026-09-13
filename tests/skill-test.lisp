(in-package #:steer-protocol/tests)

;;; Literal LF (not FORMAT). Windows CRLF checkout turns `~\` line
;;; continuations into `~\r`, which SBCL FORMATTER rejects.
(defparameter *nl* (string #\Newline))
(defparameter *tools-markdown*
  (uiop:strcat
   "---" *nl*
   "name: review" *nl*
   "description: PRs" *nl*
   "tools: lookup, grep" *nl*
   "---" *nl*
   *nl*
   "## body" *nl*
   *nl*
   "Do the review." *nl*
   *nl*
   "## tools" *nl*
   *nl*
   "### lookup" *nl*
   *nl*
   "description: Look up a symbol" *nl*
   *nl*
   "name: lookup" *nl*
   *nl*
   "### grep" *nl*
   *nl*
   "description: Search the tree" *nl*)))

(deftest parse-skill-tools-section
  (multiple-value-bind (fm body tools)
      (steer-protocol:parse-skill-markdown *tools-markdown*)
    (ok (equal "review" (getf fm :name)))
    (ok (search "Do the review." body))
    (ok (= 2 (length tools)))
    (ok (every #'llm-protocol:llm-tool-p tools))
    (ok (equal "lookup" (llm-protocol:llm-tool-name (first tools))))
    (ok (search "Look up a symbol" (llm-protocol:llm-tool-description (first tools))))
    (ok (equal "grep" (llm-protocol:llm-tool-name (second tools))))
    (ok (search "Search the tree" (llm-protocol:llm-tool-description (second tools))))))

(deftest parse-skill-tools-frontmatter-only
  (multiple-value-bind (fm body tools)
      (steer-protocol:parse-skill-markdown
       (format nil "---~%name: x~%tools: lookup, grep~%---~%Just text.~%"))
    (declare (ignore fm body))
    (ok (equal '("lookup" "grep")
               (mapcar #'llm-protocol:llm-tool-name tools)))))

(deftest load-skill-exposes-skill-tools
  (uiop:with-temporary-file (:pathname p :stream s :prefix "skill-tools" :type "md")
    (write-string *tools-markdown* s)
    (finish-output s)
    (close s)
    (let* ((d (steer-protocol:load-skill p))
           (tools (steer-protocol:skill-tools d)))
      (ok (eq :skill (steer-protocol:steer-directive-kind d)))
      (ok (= 2 (length tools)))
      (ok (equal "lookup" (llm-protocol:llm-tool-name (first tools)))))))

(deftest skill-tool-fn-register
  (let ((sk (steer-protocol:make-steer-skill "review")))
    (steer-protocol:register-skill-tool-fn
     sk "lookup" (lambda (args)
                   (declare (ignore args))
                   "hit"))
    (ok (functionp (steer-protocol:skill-tool-fn sk "lookup")))
    (ok (equal "hit" (funcall (steer-protocol:skill-tool-fn sk "lookup") nil)))
    (ok (null (steer-protocol:skill-tool-fn sk "missing")))))

(deftest skill-tool-fn-extra-plist
  (let ((sk (steer-protocol:make-steer-skill
             "review"
             :extra (list :tools (list "lookup" (lambda (args)
                                                  (declare (ignore args))
                                                  "plist")
                                       :grep 'identity)))))
    (ok (functionp (steer-protocol:skill-tool-fn sk "lookup")))
    (ok (eq 'identity (steer-protocol:skill-tool-fn sk "grep")))
    (ok (equal "plist" (funcall (steer-protocol:skill-tool-fn sk "lookup") nil)))))
