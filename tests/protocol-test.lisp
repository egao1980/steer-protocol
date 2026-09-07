(in-package #:steer-protocol/tests)

(deftest compile-rule-and-skill
  (let* ((src (steer-protocol:make-in-memory-steering
               (list (steer-protocol:make-steer-rule "cite"
                                                     :body "Always cite sources.")
                     (steer-protocol:make-steer-skill "review"
                                                      :description "Review PRs"
                                                      :body "Check tests."))))
         (text (steer-protocol:compile-steering src)))
    (ok (search "# rule: cite" text))
    (ok (search "Always cite sources." text))
    (ok (search "# skill: review" text))
    (ok (search "Review PRs" text))
    (ok (search "Check tests." text))))

(deftest disabled-directive-skipped
  (let ((src (steer-protocol:make-in-memory-steering
              (list (steer-protocol:make-steer-rule "on" :body "keep")
                    (steer-protocol:make-steer-rule "off" :body "drop"
                                                    :enabled-p nil)))))
    (ok (search "keep" (steer-protocol:compile-steering src)))
    (ng (search "drop" (steer-protocol:compile-steering src)))))

(deftest apply-steering-prepends-system
  (let* ((src (steer-protocol:make-in-memory-steering
               (steer-protocol:make-steer-rule "brief" :body "Be terse.")))
         (turns (steer-protocol:apply-steering "hi" src)))
    (ok (eq :system (llm-protocol:llm-turn-role (first turns))))
    (ok (search "Be terse." (llm-protocol:turn-text (first turns))))
    (ok (eq :user (llm-protocol:llm-turn-role (second turns))))
    (ok (equal "hi" (llm-protocol:turn-text (second turns))))))

(deftest apply-steering-merges-existing-system
  (let* ((src (steer-protocol:make-in-memory-steering
               (steer-protocol:make-steer-rule "cite" :body "Cite.")))
         (turns (steer-protocol:apply-steering
                 (list (llm-protocol:system-turn "Be brief.")
                       (llm-protocol:user-turn "hi"))
                 src)))
    (ok (search "Be brief." (llm-protocol:turn-text (first turns))))
    (ok (search "Cite." (llm-protocol:turn-text (first turns))))
    (ok (eq :user (llm-protocol:llm-turn-role (second turns))))))

(deftest register-replaces-by-name
  (let ((src (steer-protocol:make-in-memory-steering)))
    (steer-protocol:register-directive
     src (steer-protocol:make-steer-rule "x" :body "one"))
    (steer-protocol:register-directive
     src (steer-protocol:make-steer-rule "x" :body "two"))
    (ok (= 1 (length (steer-protocol:list-directives src))))
    (ok (equal "two" (steer-protocol:steer-directive-body
                      (steer-protocol:find-directive src "x"))))))

(deftest parse-skill-markdown-frontmatter
  (multiple-value-bind (fm body)
      (steer-protocol:parse-skill-markdown
       (format nil "---~%name: review~%description: PRs~%---~%~%Check tests.~%"))
    (ok (equal "review" (getf fm :name)))
    (ok (equal "PRs" (getf fm :description)))
    (ok (equal "Check tests." body))))

(deftest parse-skill-markdown-plain
  (multiple-value-bind (fm body)
      (steer-protocol:parse-skill-markdown "just a rule")
    (ok (null fm))
    (ok (equal "just a rule" body))))

(deftest load-skill-file
  (uiop:with-temporary-file (:pathname p :stream s :prefix "skill" :type "md")
    (write-string (format nil "---~%name: tmp~%description: t~%---~%Do X.~%") s)
    (finish-output s)
    (close s)
    (let ((d (steer-protocol:load-skill p)))
      (ok (eq :skill (steer-protocol:steer-directive-kind d)))
      (ok (equal "tmp" (steer-protocol:steer-directive-name d)))
      (ok (equal "Do X." (steer-protocol:steer-directive-body d))))))

(deftest load-skills-from-directory
  (let* ((root (uiop:ensure-directory-pathname
                (merge-pathnames (format nil "steer-test-~a/" (random 100000))
                                 (uiop:temporary-directory))))
         (nested (merge-pathnames "nested/" root)))
    (unwind-protect
         (progn
           (ensure-directories-exist nested)
           (with-open-file (s (merge-pathnames "SKILL.md" root)
                              :direction :output :if-exists :supersede)
             (write-string (format nil "---~%name: root~%---~%R~%") s))
           (with-open-file (s (merge-pathnames "SKILL.md" nested)
                              :direction :output :if-exists :supersede)
             (write-string (format nil "---~%name: nest~%---~%N~%") s))
           (let ((ds (steer-protocol:load-skills-from-directory root)))
             (ok (= 2 (length ds)))
             (ok (equal '("root" "nest")
                        (mapcar #'steer-protocol:steer-directive-name ds)))))
      (uiop:delete-directory-tree root :validate t :if-does-not-exist :ignore))))

(deftest coerce-steering-shapes
  (let ((d (steer-protocol:make-steer-rule "r" :body "x")))
    (ok (steer-protocol:steering-source-p (steer-protocol:coerce-steering d)))
    (ok (steer-protocol:steering-source-p
         (steer-protocol:coerce-steering (list d))))
    (ok (null (steer-protocol:coerce-steering nil)))))

(deftest list-directives-accepts-mixed-list
  (let ((d (steer-protocol:make-steer-rule "r" :body "x"))
        (src (steer-protocol:make-in-memory-steering
              (steer-protocol:make-steer-skill "s" :body "y"))))
    (ok (equal '("r" "s")
               (mapcar #'steer-protocol:steer-directive-name
                       (steer-protocol:list-directives (list d src)))))))
