(in-package #:steer-protocol/tests)

(defun %write-file (path text)
  (ensure-directories-exist path)
  (with-open-file (s path :direction :output :if-exists :supersede
                          :external-format :utf-8)
    (write-string text s)))

(defmacro with-project ((root) &body body)
  `(let ((,root (uiop:ensure-directory-pathname
                 (merge-pathnames (format nil "steer-instr-~a/" (random 1000000))
                                  (uiop:temporary-directory)))))
     (unwind-protect
          (progn
            (ensure-directories-exist ,root)
            (setf ,root (truename ,root))
            ,@body)
       (uiop:delete-directory-tree ,root :validate t :if-does-not-exist :ignore))))

(defun %names (directives)
  (mapcar #'steer-protocol:steer-directive-name directives))

(deftest discover-walks-up-to-root
  (with-project (root)
    (%write-file (merge-pathnames "AGENTS.md" root) "root rules")
    (%write-file (merge-pathnames "src/AGENTS.md" root) "src rules")
    (%write-file (merge-pathnames "src/deep/x.lisp" root) "(x)")
    (%write-file (merge-pathnames "other/AGENTS.md" root) "other rules")
    (let* ((disc (steer-protocol:make-instruction-discovery root))
           (found (steer-protocol:discover-instructions disc "src/deep/x.lisp")))
      (ok (equal '("AGENTS.md" "src/AGENTS.md") (%names found)))
      (ok (every (lambda (d) (eq :rule (steer-protocol:steer-directive-kind d))) found))
      (ok (equal "src rules" (steer-protocol:steer-directive-body (second found))))
      (ok (equal (merge-pathnames "src/" root)
                 (getf (steer-protocol:steer-directive-extra (second found)) :scope)))
      (testing "already injected → nothing new"
        (ok (null (steer-protocol:discover-instructions
                   disc (merge-pathnames "src/deep/x.lisp" root)))))
      (testing "sibling directory only adds its own file"
        (ok (equal '("other/AGENTS.md")
                   (%names (steer-protocol:discover-instructions disc "other/y.txt")))))
      (ok (equal '("AGENTS.md" "src/AGENTS.md" "other/AGENTS.md")
                 (%names (steer-protocol:list-directives disc)))))))

(deftest discover-outside-root-is-empty
  (with-project (root)
    (%write-file (merge-pathnames "AGENTS.md" root) "r")
    (let ((disc (steer-protocol:make-instruction-discovery
                 (merge-pathnames "sub/" root))))
      (ensure-directories-exist (merge-pathnames "sub/" root))
      (ok (null (steer-protocol:discover-instructions
                 disc (merge-pathnames "AGENTS.md" root))))
      (ok (null (steer-protocol:discover-instructions disc "../AGENTS.md"))))))

(deftest discover-names-and-per-directory
  (with-project (root)
    (%write-file (merge-pathnames "AGENTS.md" root) "a")
    (%write-file (merge-pathnames "CLAUDE.md" root) "c")
    (%write-file (merge-pathnames "lib/CLAUDE.md" root) "lib c")
    (testing "default: AGENTS.md only"
      (ok (equal '("AGENTS.md")
                 (%names (steer-protocol:discover-instructions
                          (steer-protocol:make-instruction-discovery root)
                          "lib/f.lisp")))))
    (testing "include-claude, first per directory"
      (ok (equal '("AGENTS.md" "lib/CLAUDE.md")
                 (%names (steer-protocol:discover-instructions
                          (steer-protocol:make-instruction-discovery
                           root :include-claude t)
                          "lib/f.lisp")))))
    (testing ":all per directory"
      (ok (equal '("AGENTS.md" "CLAUDE.md" "lib/CLAUDE.md")
                 (%names (steer-protocol:discover-instructions
                          (steer-protocol:make-instruction-discovery
                           root :names '("AGENTS.md" "CLAUDE.md") :per-directory :all)
                          "lib/f.lisp")))))
    (testing "include-root nil skips the root file"
      (ok (equal '("lib/CLAUDE.md")
                 (%names (steer-protocol:discover-instructions
                          (steer-protocol:make-instruction-discovery
                           root :names '("CLAUDE.md") :include-root nil)
                          "lib/f.lisp")))))))

(deftest forget-re-injects
  (with-project (root)
    (%write-file (merge-pathnames "AGENTS.md" root) "r")
    (%write-file (merge-pathnames "a/AGENTS.md" root) "a")
    (let ((disc (steer-protocol:make-instruction-discovery root)))
      (ok (= 2 (length (steer-protocol:discover-instructions disc "a/f"))))
      (ok (steer-protocol:instruction-injected-p disc "a/AGENTS.md"))
      (steer-protocol:forget-instructions disc :path "a/AGENTS.md")
      (ng (steer-protocol:instruction-injected-p disc "a/AGENTS.md"))
      (ok (equal '("a/AGENTS.md")
                 (%names (steer-protocol:discover-instructions disc "a/f"))))
      (ok (eq disc (steer-protocol:forget-instructions disc)))
      (ok (null (steer-protocol:list-directives disc)))
      (ok (equal '("AGENTS.md" "a/AGENTS.md")
                 (%names (steer-protocol:discover-instructions disc "a/f")))))))

(deftest changed-content-re-injects
  (with-project (root)
    (let ((file (merge-pathnames "AGENTS.md" root))
          (disc (steer-protocol:make-instruction-discovery root)))
      (%write-file file "version one")
      (ok (= 1 (length (steer-protocol:discover-instructions disc "x"))))
      (ok (null (steer-protocol:discover-instructions disc "x")))
      (%write-file file "version two")
      (ng (steer-protocol:instruction-injected-p disc file))
      (let ((again (steer-protocol:discover-instructions disc "x")))
        (ok (equal "version two" (steer-protocol:steer-directive-body (first again)))))
      (ok (= 1 (length (steer-protocol:list-directives disc))))
      (ok (equal "version two" (steer-protocol:steer-directive-body
                                (first (steer-protocol:list-directives disc))))))))

(deftest copy-discovery
  (with-project (root)
    (%write-file (merge-pathnames "AGENTS.md" root) "r")
    (let ((disc (steer-protocol:make-instruction-discovery root :include-claude t)))
      (steer-protocol:discover-instructions disc "x")
      (let ((fresh (steer-protocol:copy-instruction-discovery disc))
            (kept (steer-protocol:copy-instruction-discovery disc :keep-injected t)))
        (ok (equal (steer-protocol:instruction-discovery-names disc)
                   (steer-protocol:instruction-discovery-names fresh)))
        (ok (null (steer-protocol:list-directives fresh)))
        (ok (= 1 (length (steer-protocol:discover-instructions fresh "x"))))
        (ok (null (steer-protocol:discover-instructions kept "x")))
        (ok (= 1 (length (steer-protocol:list-directives disc))))))))

(deftest mark-nil-peeks
  (with-project (root)
    (%write-file (merge-pathnames "AGENTS.md" root) "r")
    (let* ((disc (steer-protocol:make-instruction-discovery root))
           (peek (steer-protocol:discover-instructions disc "x" :mark nil)))
      (ok (= 1 (length peek)))
      (ok (= 1 (length (steer-protocol:discover-instructions disc "x" :mark nil))))
      (steer-protocol:mark-instructions-injected disc peek)
      (ok (null (steer-protocol:discover-instructions disc "x"))))))

(deftest discover-path-list-and-compile
  (with-project (root)
    (%write-file (merge-pathnames "AGENTS.md" root) "root says hi")
    (%write-file (merge-pathnames "a/AGENTS.md" root) "a says hi")
    (let* ((disc (steer-protocol:make-instruction-discovery root))
           (found (steer-protocol:discover-instructions disc '("a/x" "b/y")))
           (text (steer-protocol:compile-instructions found)))
      (ok (equal '("AGENTS.md" "a/AGENTS.md") (%names found)))
      (ok (search "<instructions path=\"a/AGENTS.md\" scope=\"a/\">" text))
      (ok (search "root says hi" text))
      (ok (search "# rule: a/AGENTS.md" (steer-protocol:compile-steering disc)))
      (ok (equal "" (steer-protocol:compile-instructions nil))))))

(deftest coerce-discovery-shapes
  (with-project (root)
    (ok (null (steer-protocol:coerce-instruction-discovery nil)))
    (ok (steer-protocol:instruction-discovery-p
         (steer-protocol:coerce-instruction-discovery root)))
    (let ((d (steer-protocol:coerce-instruction-discovery
              (list :root root :include-claude t))))
      (ok (member "CLAUDE.md" (steer-protocol:instruction-discovery-names d)
                  :test #'equal))
      (ok (eq d (steer-protocol:coerce-instruction-discovery d))))))

(deftest content-hash-stable
  (let ((disc (steer-protocol:make-instruction-discovery (uiop:temporary-directory))))
    (ok (equal (steer-protocol:instruction-content-hash disc "abc")
               (steer-protocol:instruction-content-hash disc "abc")))
    (ng (equal (steer-protocol:instruction-content-hash disc "abc")
               (steer-protocol:instruction-content-hash disc "abd")))
    (ok (= 16 (length (steer-protocol:instruction-content-hash disc ""))))))

(defclass broken-discovery (steer-protocol:instruction-discovery) ())

(defmethod steer-protocol:instruction-candidates ((d broken-discovery) path &key)
  (declare (ignore path))
  (list (merge-pathnames "missing/AGENTS.md" (steer-protocol:instruction-discovery-root d))))

(defun %broken (root)
  (change-class (steer-protocol:make-instruction-discovery root) 'broken-discovery))

(deftest unreadable-signals
  (with-project (root)
    (ok (signals (steer-protocol:discover-instructions (%broken root) "x")
                 'steer-protocol:steer-instruction-unreadable))))

(deftest unreadable-continue-skips
  (with-project (root)
    (let ((got :unset))
      (handler-bind ((steer-protocol:steer-instruction-unreadable
                       (lambda (c) (continue c))))
        (setf got (steer-protocol:discover-instructions (%broken root) "x")))
      (ok (null got)))))

(deftest unreadable-use-value
  (with-project (root)
    (let ((got nil))
      (handler-bind ((steer-protocol:steer-instruction-unreadable
                       (lambda (c)
                         (ok (steer-protocol:steer-instruction-unreadable-cause c))
                         (use-value "fallback" c))))
        (setf got (steer-protocol:discover-instructions (%broken root) "x")))
      (ok (equal "fallback" (steer-protocol:steer-directive-body (first got)))))))
