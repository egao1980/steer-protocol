(in-package #:steer-protocol)

;;; Versioned skill store. Default backend writes SKILL.md and shells git
;;; (process-protocol:run when *process-backend* is bound, else UIOP).
;;; file-skill-store keeps numbered SKILL.md.<n> files for git-less tests.

(defclass skill-store ()
  ((root :initarg :root :accessor skill-store-root)))

(defun skill-store-p (x)
  (typep x 'skill-store))

(defclass file-skill-store (skill-store) ())

(defclass git-skill-store (file-skill-store) ())

(defun make-file-skill-store (root)
  (make-instance 'file-skill-store
                 :root (uiop:ensure-directory-pathname root)))

(defun make-git-skill-store (root)
  (make-instance 'git-skill-store
                 :root (uiop:ensure-directory-pathname root)))

(defclass skill-version ()
  ((id :initarg :id :accessor skill-version-id)
   (timestamp :initarg :timestamp :accessor skill-version-timestamp :initform nil)
   (provenance :initarg :provenance :accessor skill-version-provenance
               :initform nil)
   (name :initarg :name :accessor skill-version-name :initform nil)))

(defun make-skill-version (&key id timestamp provenance name)
  (make-instance 'skill-version
                 :id id :timestamp timestamp
                 :provenance provenance :name name))

(defun skill-version-p (x)
  (typep x 'skill-version))

(defgeneric save-skill-version (store skill &key provenance)
  (:documentation "Persist SKILL as a new version. → skill-version.
   PROVENANCE is a plist (improvement-cycle / eval-run ids, …)."))

(defgeneric skill-versions (store name &key)
  (:documentation "Version records for NAME, newest first."))

(defgeneric rollback-skill (store name version &key)
  (:documentation "Restore NAME's working file to VERSION. → directive."))

(defgeneric load-skill-version (store name version &key)
  (:documentation "Load NAME at VERSION without changing the working file."))

(defun git-available-p ()
  "T when `git --version` exits 0."
  (ignore-errors
    (zerop (nth-value 2
                      (uiop:run-program '("git" "--version")
                                        :ignore-error-status t
                                        :output :string
                                        :error-output :string)))))

(defun %skill-dir (store name)
  (merge-pathnames (uiop:ensure-directory-pathname name)
                   (skill-store-root store)))

(defun %skill-md (store name)
  (merge-pathnames "SKILL.md" (%skill-dir store name)))

(defun %skill-provenance-file (store name)
  (merge-pathnames ".provenance" (%skill-dir store name)))

(defun %version-md (store name n)
  (merge-pathnames (format nil "SKILL.md.~d" n) (%skill-dir store name)))

(defun %version-provenance-file (store name n)
  (merge-pathnames (format nil "SKILL.md.~d.provenance" n)
                   (%skill-dir store name)))

(defun %read-provenance (path)
  (when (probe-file path)
    (with-open-file (s path :direction :input)
      (ignore-errors (read s nil nil)))))

(defun %write-text (path text)
  (ensure-directories-exist path)
  (with-open-file (s path :direction :output :if-exists :supersede
                         :if-does-not-exist :create)
    (write-string (or text "") s)
    (unless (and text
                 (plusp (length text))
                 (char= (char text (1- (length text))) #\Newline))
      (terpri s)))
  path)

(defun %write-provenance (path provenance)
  (%write-text path (with-output-to-string (o)
                      (prin1 (or provenance nil) o)
                      (terpri o))))

(defun %write-working-skill (store skill provenance)
  (let ((name (steer-directive-name skill)))
    (%write-text (%skill-md store name) (serialize-skill-markdown skill))
    (%write-provenance (%skill-provenance-file store name) provenance)
    name))

(defun %file-version-count (store name)
  (let ((n 0))
    (loop for i from 1
          while (probe-file (%version-md store name i))
          do (setf n i))
    n))

(defun %signal-unknown-version (store name version)
  (restart-case
      (error 'steer-unknown-version
             :store store
             :name name
             :version version
             :message (format nil "no version ~s for ~s" version name))
    (use-value (value)
      :report "Use a supplied skill or version"
      value)
    (continue ()
      :report "Skip missing version"
      nil)))

(defun %coerce-version-id (version)
  (cond
    ((skill-version-p version) (skill-version-id version))
    ((integerp version) (princ-to-string version))
    (t (string version))))

(defmethod save-skill-version ((store file-skill-store) skill &key provenance)
  (check-type skill steer-directive)
  (let* ((name (%write-working-skill store skill provenance))
         (n (1+ (%file-version-count store name))))
    (uiop:copy-file (%skill-md store name) (%version-md store name n))
    (%write-provenance (%version-provenance-file store name n) provenance)
    (make-skill-version :id (princ-to-string n)
                        :timestamp (get-universal-time)
                        :provenance provenance
                        :name name)))

(defmethod skill-versions ((store file-skill-store) name &key)
  (loop for i from (%file-version-count store name) downto 1
        collect (make-skill-version
                 :id (princ-to-string i)
                 :timestamp (and (probe-file (%version-md store name i))
                                 (file-write-date (%version-md store name i)))
                 :provenance (%read-provenance
                              (%version-provenance-file store name i))
                 :name name)))

(defmethod load-skill-version ((store file-skill-store) name version &key)
  (let* ((id (%coerce-version-id version))
         (n (parse-integer id :junk-allowed t))
         (path (and n (%version-md store name n))))
    (if (and path (probe-file path))
        (load-skill path)
        (%signal-unknown-version store name version))))

(defmethod rollback-skill ((store file-skill-store) name version &key)
  (let ((skill (load-skill-version store name version)))
    (when skill
      (%write-text (%skill-md store name) (serialize-skill-markdown skill))
      (%write-provenance (%skill-provenance-file store name)
                         (let ((n (parse-integer (%coerce-version-id version)
                                                 :junk-allowed t)))
                           (and n (%read-provenance
                                   (%version-provenance-file store name n)))))
      (load-skill (%skill-md store name)))))

;;; --- git -------------------------------------------------------------------

(defun %process-protocol-run ()
  (let ((pkg (find-package '#:process-protocol)))
    (when pkg
      (let ((star (find-symbol "*PROCESS-BACKEND*" pkg))
            (run (find-symbol "RUN" pkg)))
        (when (and star run (boundp star) (symbol-value star) (fboundp run))
          run)))))

(defun %to-string (x)
  (cond
    ((stringp x) x)
    ((null x) "")
    ((and (vectorp x)
          (plusp (length x))
          (not (characterp (aref x 0))))
     (map 'string #'code-char x))
    (t (princ-to-string x))))

(defun %git-relpath (store path)
  (substitute #\/ #\\
              (namestring (enough-namestring path (skill-store-root store)))))

(defun %run-git (store args &key identity)
  "Run git in STORE's root. → (values exit-code stdout stderr)."
  (let* ((argv (append '("git")
                       (when identity
                         '("-c" "user.name=steer-protocol"
                           "-c" "user.email=steer@localhost"
                           "-c" "commit.gpgsign=false"))
                       args))
         (dir (skill-store-root store))
         (run (%process-protocol-run)))
    (if run
        (multiple-value-bind (code out err)
            (funcall run argv :directory dir)
          (values (or code 0) (%to-string out) (%to-string err)))
        (multiple-value-bind (out err code)
            (uiop:run-program argv
                              :directory dir
                              :ignore-error-status t
                              :output '(:string :stripped nil)
                              :error-output '(:string :stripped nil))
          (values (or code 0) (or out "") (or err ""))))))

(defun %git-ok (store args &key identity)
  (multiple-value-bind (code out err)
      (%run-git store args :identity identity)
    (unless (zerop code)
      (error 'steer-skill-store-error
             :store store
             :message (format nil "git ~{~a~^ ~} failed (~a): ~a"
                              args code
                              (string-trim '(#\Space #\Tab #\Newline) err))))
    (values out err)))

(defun %format-commit-message (skill provenance)
  (with-output-to-string (o)
    (format o "steer: save skill ~a~%" (steer-directive-name skill))
    (when provenance
      (format o "~%")
      (prin1 provenance o)
      (terpri o))))

(defun %parse-commit-provenance (body)
  (let ((start (position #\( body)))
    (if start
        (ignore-errors
          (let ((*read-eval* nil))
            (read-from-string body t nil :start start)))
        nil)))

(defun %git-log-records (store relpath)
  (multiple-value-bind (code out err)
      (%run-git store (list "log" "--follow"
                            "--pretty=format:%H%x09%cI%x09%B%x1e"
                            "--" relpath))
    (declare (ignore err))
    (unless (zerop code)
      (return-from %git-log-records nil))
    (let ((records '())
          (rs (string (code-char #x1e))))
      (dolist (chunk (uiop:split-string out :separator (coerce rs 'list)))
        (let ((chunk (string-trim '(#\Newline #\Return #\Space #\Tab) chunk)))
          (when (plusp (length chunk))
            (let ((tab (position #\Tab chunk)))
              (when tab
                (let* ((hash (subseq chunk 0 tab))
                       (rest (subseq chunk (1+ tab)))
                       (tab2 (position #\Tab rest)))
                  (when tab2
                    (push (list hash
                                (subseq rest 0 tab2)
                                (%parse-commit-provenance (subseq rest (1+ tab2))))
                          records))))))))
      (nreverse records))))

(defmethod save-skill-version ((store git-skill-store) skill &key provenance)
  (check-type skill steer-directive)
  (let* ((name (%write-working-skill store skill provenance))
         (md (%skill-md store name))
         (prov (%skill-provenance-file store name))
         (rel-md (%git-relpath store md))
         (rel-prov (%git-relpath store prov)))
    (%git-ok store (list "add" "--" rel-md rel-prov))
    (%git-ok store (list "commit" "--allow-empty" "-m"
                         (%format-commit-message skill provenance))
             :identity t)
    (let ((hash (string-trim '(#\Newline #\Return #\Space #\Tab)
                             (%git-ok store '("rev-parse" "HEAD")))))
      (make-skill-version :id hash
                          :timestamp (get-universal-time)
                          :provenance provenance
                          :name name))))

(defmethod skill-versions ((store git-skill-store) name &key)
  (let ((rel (%git-relpath store (%skill-md store name))))
    (mapcar (lambda (rec)
              (make-skill-version :id (first rec)
                                  :timestamp (second rec)
                                  :provenance (third rec)
                                  :name name))
            (%git-log-records store rel))))

(defmethod load-skill-version ((store git-skill-store) name version &key)
  (let* ((id (%coerce-version-id version))
         (rel (%git-relpath store (%skill-md store name))))
    (multiple-value-bind (code out err)
        (%run-git store (list "show" (format nil "~a:~a" id rel)))
      (declare (ignore err))
      (if (zerop code)
          (multiple-value-bind (fm body tools)
              (parse-skill-markdown out)
            (make-steer-directive
             :kind :skill
             :name (or (getf fm :name) name)
             :description (getf fm :description)
             :body body
             :extra (%extra-with-tools fm tools)))
          (%signal-unknown-version store name version)))))

(defmethod rollback-skill ((store git-skill-store) name version &key)
  (let* ((id (%coerce-version-id version))
         (md (%skill-md store name))
         (prov (%skill-provenance-file store name))
         (rel-md (%git-relpath store md))
         (rel-prov (%git-relpath store prov)))
    (multiple-value-bind (code out err)
        (%run-git store (list "checkout" id "--" rel-md))
      (declare (ignore out err))
      (unless (zerop code)
        (return-from rollback-skill
          (%signal-unknown-version store name version)))
      (%run-git store (list "checkout" id "--" rel-prov))
      (load-skill md))))
