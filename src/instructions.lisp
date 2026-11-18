(in-package #:steer-protocol)

;;; Lazily discovered, path-scoped instructions (0.3).
;;;
;;; The agent reads or touches a file. DISCOVER-INSTRUCTIONS walks from the
;;; file's directory up to the project root and returns the AGENTS.md (or
;;; configured names) not yet injected, as :rule directives scoped to their
;;; directory. The source remembers what it injected and the content hash;
;;; a changed file is returned again. FORGET-INSTRUCTIONS after a compaction
;;; drops that memory so the next discovery re-injects.

(defparameter *default-instruction-names* '("AGENTS.md")
  "File names INSTRUCTION-DISCOVERY looks for, in priority order.")

(defclass instruction-discovery (steering-source)
  ((root :initarg :root :reader instruction-discovery-root)
   (names :initarg :names :accessor instruction-discovery-names
          :initform (copy-list *default-instruction-names*))
   (per-directory :initarg :per-directory
                  :accessor instruction-discovery-per-directory
                  :initform :first
                  :documentation ":FIRST takes the first name found in each
   directory; :ALL takes every name found.")
   (include-root :initarg :include-root
                 :accessor instruction-discovery-include-root-p
                 :initform t)
   (injected :initform (make-hash-table :test #'equal)
             :reader %injected-table
             :documentation "namestring → directive (its extra carries :hash).")
   (order :initform '() :accessor %injected-order))
  (:documentation "STEERING-SOURCE of path-scoped instruction files found on
   demand. LIST-DIRECTIVES → the directives injected and still in context."))

(defun instruction-discovery-p (x)
  (typep x 'instruction-discovery))

(defun %root-directory (root)
  (let ((dir (uiop:ensure-directory-pathname root)))
    (or (uiop:directory-exists-p dir) dir)))

(defun make-instruction-discovery (root &key (names *default-instruction-names*)
                                          include-claude
                                          (per-directory :first)
                                          (include-root t))
  "Discovery source rooted at ROOT. NAMES are file names in priority order;
   INCLUDE-CLAUDE appends \"CLAUDE.md\". PER-DIRECTORY is :FIRST or :ALL."
  (check-type per-directory (member :first :all))
  (let ((names (if (stringp names) (list names) (copy-list names))))
    (assert (every #'stringp names) (names)
            "instruction NAMES must be strings: ~s" names)
    (when (and include-claude (not (member "CLAUDE.md" names :test #'string=)))
      (setf names (append names (list "CLAUDE.md"))))
    (make-instance 'instruction-discovery
                   :root (%root-directory root)
                   :names names
                   :per-directory per-directory
                   :include-root include-root)))

(defun coerce-instruction-discovery (x)
  "X as an INSTRUCTION-DISCOVERY: one itself, NIL, a root path designator, or
   a plist (:root dir . make-instruction-discovery keys)."
  (etypecase x
    (null nil)
    (instruction-discovery x)
    ((or string pathname) (make-instruction-discovery x))
    (cons (apply #'make-instruction-discovery (getf x :root)
                 (loop for (k v) on x by #'cddr
                       unless (eq k :root) nconc (list k v))))))

(defgeneric copy-instruction-discovery (discovery &key keep-injected)
  (:documentation "Same class and configuration as DISCOVERY. The copy's
   injected memory is empty unless KEEP-INJECTED. Use one copy per agent run:
   what is in context belongs to the run, not the shared configuration.")
  (:method ((discovery instruction-discovery) &key keep-injected)
   (let ((new (make-instance (class-of discovery)
                             :root (instruction-discovery-root discovery)
                             :names (copy-list (instruction-discovery-names discovery))
                             :per-directory (instruction-discovery-per-directory discovery)
                             :include-root (instruction-discovery-include-root-p discovery))))
     (when keep-injected
       (maphash (lambda (k v) (setf (gethash k (%injected-table new)) v))
                (%injected-table discovery))
       (setf (%injected-order new) (copy-list (%injected-order discovery))))
     new)))

(defgeneric instruction-candidates (discovery path &key)
  (:documentation "Existing instruction files that apply to PATH, outermost
   (root) first. PATH outside the root → NIL."))

(defgeneric discover-instructions (discovery path &key mark)
  (:documentation "New or changed instruction directives for PATH (a path
   designator or a list of them), outermost first. MARK (default T) records
   them as injected."))

(defgeneric instruction-injected-p (discovery file &key)
  (:documentation "True when FILE's current content is injected and in context."))

(defgeneric mark-instructions-injected (discovery directives &key)
  (:documentation "Record DIRECTIVES (from DISCOVER-INSTRUCTIONS :MARK NIL) as
   injected. → DIRECTIVES."))

(defgeneric forget-instructions (discovery &key path)
  (:documentation "Forget injected instructions — all, or the one file PATH —
   so the next discovery re-injects them. Call after a compaction. → DISCOVERY."))

(defgeneric instruction-content-hash (discovery text)
  (:documentation "Change-detection hash of TEXT (a string). Default: FNV-1a
   64-bit over char codes, as lowercase hex. Not a security hash."))

(defmethod instruction-content-hash ((discovery t) (text string))
  (let ((h #xcbf29ce484222325))
    (declare (type (unsigned-byte 64) h))
    (loop for ch across text
          do (setf h (ldb (byte 64 0)
                          (* (logxor h (char-code ch)) #x100000001b3))))
    (format nil "~(~16,'0x~)" h)))

(defun %coerce-path (discovery path)
  (let ((p (etypecase path
             (pathname path)
             (string (uiop:parse-native-namestring path)))))
    (uiop:truenamize
     (if (uiop:absolute-pathname-p p)
         p
         (merge-pathnames p (instruction-discovery-root discovery))))))

(defun %start-directory (path)
  (if (or (uiop:directory-pathname-p path) (uiop:directory-exists-p path))
      (uiop:ensure-directory-pathname path)
      (uiop:pathname-directory-pathname path)))

(defun %directory-chain (root dir)
  "Directory pathnames from ROOT down to DIR; NIL when DIR is not under ROOT."
  (let* ((rc (pathname-directory root))
         (dc (pathname-directory dir))
         (n (length rc)))
    (when (and (eq :absolute (first dc))
               (>= (length dc) n)
               (equal rc (subseq dc 0 n))
               (notany (lambda (c) (member c '(:up :back))) dc))
      (loop for i from n to (length dc)
            collect (make-pathname :directory (subseq dc 0 i)
                                   :name nil :type nil :version nil
                                   :defaults root)))))

(defmethod instruction-candidates ((discovery instruction-discovery) path &key)
  (let* ((root (instruction-discovery-root discovery))
         (chain (%directory-chain root (%start-directory
                                        (%coerce-path discovery path)))))
    (unless (instruction-discovery-include-root-p discovery)
      (setf chain (rest chain)))
    (loop for dir in chain
          nconc (let ((found (loop for name in (instruction-discovery-names discovery)
                                   for f = (probe-file (merge-pathnames name dir))
                                   when (and f (not (uiop:directory-pathname-p f)))
                                     collect f)))
                  (if (eq :first (instruction-discovery-per-directory discovery))
                      (and found (list (first found)))
                      found)))))

(defun %file-key (file)
  (namestring file))

(defun %read-instruction-text (file)
  "FILE contents. Unreadable → STEER-INSTRUCTION-UNREADABLE with USE-VALUE
   (text to use) and CONTINUE (skip the file → NIL)."
  (restart-case
      (handler-case (uiop:read-file-string file :external-format :utf-8)
        ((or file-error stream-error) (c)
          (error 'steer-instruction-unreadable
                 :path file :cause c
                 :message (format nil "cannot read ~a" (namestring file)))))
    (use-value (text)
      :report "Use supplied instruction text"
      :interactive (lambda ()
                     (format *query-io* "Instruction text: ")
                     (force-output *query-io*)
                     (list (read-line *query-io*)))
      text)
    (continue ()
      :report "Skip this instruction file"
      nil)))

(defun %relative-name (discovery file)
  "FILE relative to the root, with / separators on every platform. A
   directory pathname → \"a/b/\" (root itself → \"\")."
  (let* ((rel (uiop:enough-pathname file (instruction-discovery-root discovery)))
         (dirs (rest (pathname-directory rel))))
    (format nil "~{~a/~}~@[~a~]"
            (mapcar #'string dirs)
            (and (pathname-name rel) (file-namestring rel)))))

(defun %instruction-directive (discovery file text hash)
  (let* ((scope (uiop:pathname-directory-pathname file))
         (rel-scope (%relative-name discovery scope))
         (rel-scope (if (zerop (length rel-scope)) "./" rel-scope)))
    (make-steer-directive
     :kind :rule
     :name (%relative-name discovery file)
     :description (format nil "Instructions for files under ~a" rel-scope)
     :body (string-trim '(#\Space #\Tab #\Newline #\Return) text)
     :path file
     :extra (list :instructions t :scope scope :scope-name rel-scope :hash hash))))

(defun %directive-hash (directive)
  (getf (steer-directive-extra directive) :hash))

(defmethod instruction-injected-p ((discovery instruction-discovery) file &key)
  (let* ((file (%coerce-path discovery file))
         (have (gethash (%file-key file) (%injected-table discovery))))
    (and have
         (probe-file file)
         (equal (%directive-hash have)
                (instruction-content-hash
                 discovery (uiop:read-file-string file :external-format :utf-8)))
         t)))

(defmethod mark-instructions-injected ((discovery instruction-discovery) directives &key)
  (dolist (d directives directives)
    (let ((key (%file-key (steer-directive-path d))))
      (unless (gethash key (%injected-table discovery))
        (setf (%injected-order discovery)
              (append (%injected-order discovery) (list key))))
      (setf (gethash key (%injected-table discovery)) d))))

(defmethod discover-instructions ((discovery instruction-discovery) path &key (mark t))
  (let ((new '()))
    (dolist (file (instruction-candidates discovery path))
      (let ((text (%read-instruction-text file)))
        (when text
          (let ((hash (instruction-content-hash discovery text))
                (have (gethash (%file-key file) (%injected-table discovery))))
            (unless (and have (equal hash (%directive-hash have)))
              (push (%instruction-directive discovery file text hash) new))))))
    (setf new (nreverse new))
    (when mark
      (mark-instructions-injected discovery new))
    new))

(defmethod discover-instructions ((discovery instruction-discovery) (paths list)
                                  &key (mark t))
  (let ((out '()))
    (dolist (p paths (nreverse out))
      (dolist (d (discover-instructions discovery p :mark mark))
        (unless (find (steer-directive-path d) out
                      :key #'steer-directive-path :test #'equal)
          (push d out))))))

(defmethod forget-instructions ((discovery instruction-discovery) &key path)
  (if path
      (let ((key (%file-key (%coerce-path discovery path))))
        (remhash key (%injected-table discovery))
        (setf (%injected-order discovery)
              (remove key (%injected-order discovery) :test #'equal)))
      (progn
        (clrhash (%injected-table discovery))
        (setf (%injected-order discovery) '())))
  discovery)

(defmethod list-directives ((source instruction-discovery) &key)
  (loop for key in (%injected-order source)
        for d = (gethash key (%injected-table source))
        when d collect d))

(defmethod register-directive ((source instruction-discovery) directive &key)
  (check-type directive steer-directive)
  (unless (steer-directive-path directive)
    (error 'steer-error
           :message "instruction directives need a PATH (the instruction file)"))
  (unless (%directive-hash directive)
    (setf (steer-directive-extra directive)
          (list* :hash (instruction-content-hash
                        source (or (steer-directive-body directive) ""))
                 (steer-directive-extra directive))))
  (first (mark-instructions-injected source (list directive))))

(defmethod unregister-directive ((source instruction-discovery) name &key)
  (let ((found (find-directive source name)))
    (when found
      (forget-instructions source :path (steer-directive-path found)))
    source))

(defun compile-instructions (directives)
  "DIRECTIVES (from DISCOVER-INSTRUCTIONS) as one text block for an injected
   turn. Empty → \"\"."
  (with-output-to-string (o)
    (loop for (d . more) on directives
          do (format o "<instructions path=\"~a\" scope=\"~a\">~%~a~%</instructions>"
                     (steer-directive-name d)
                     (or (getf (steer-directive-extra d) :scope-name) "")
                     (steer-directive-body d))
             (when more (format o "~%~%")))))
