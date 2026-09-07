(in-package #:steer-protocol)

;;; Rules + skills as one directive type. Not A2A agent-skill. Not llm-protocol GFs.

(deftype steer-kind ()
  '(member :rule :skill))

(defclass steer-directive ()
  ((kind :initarg :kind :accessor steer-directive-kind :initform :rule)
   (name :initarg :name :accessor steer-directive-name)
   (description :initarg :description :accessor steer-directive-description
                :initform nil)
   (body :initarg :body :accessor steer-directive-body :initform "")
   (path :initarg :path :accessor steer-directive-path :initform nil)
   (enabled-p :initarg :enabled-p :accessor steer-directive-enabled-p :initform t)
   (extra :initarg :extra :accessor steer-directive-extra :initform nil)))

(defun steer-directive-p (x)
  (typep x 'steer-directive))

(defun make-steer-directive (&key (kind :rule) name description (body "") path
                               (enabled-p t) extra)
  (check-type kind steer-kind)
  (check-type name string)
  (make-instance 'steer-directive
                 :kind kind :name name :description description
                 :body (or body "") :path path :enabled-p enabled-p :extra extra))

(defun make-steer-rule (name &key description (body "") (enabled-p t) extra)
  (make-steer-directive :kind :rule :name name :description description
                        :body body :enabled-p enabled-p :extra extra))

(defun make-steer-skill (name &key description (body "") path (enabled-p t) extra)
  (make-steer-directive :kind :skill :name name :description description
                        :body body :path path :enabled-p enabled-p :extra extra))

(defclass steering-source () ())

(defun steering-source-p (x)
  (typep x 'steering-source))

(defvar *steering* nil)

(defun %ensure-source (&optional (source *steering*))
  (or source
      (restart-case
          (error 'steer-missing-source
                 :message "*steering* is nil — call MAKE-IN-MEMORY-STEERING")
        (use-value (supplied)
          :report "Use a supplied steering source"
          :interactive (lambda ()
                         (format *query-io* "Steering source: ")
                         (force-output *query-io*)
                         (list (read *query-io*)))
          supplied))))

(defgeneric list-directives (source &key)
  (:documentation "Enabled and disabled STEER-DIRECTIVE list from SOURCE."))

(defgeneric find-directive (source name &key)
  (:documentation "Directive named NAME, or STEER-UNKNOWN-DIRECTIVE
   (USE-VALUE / CONTINUE)."))

(defgeneric register-directive (source directive &key)
  (:documentation "Add or replace DIRECTIVE on SOURCE by name. → directive."))

(defgeneric unregister-directive (source name &key)
  (:documentation "Drop NAME. Missing → STEER-UNKNOWN-DIRECTIVE."))

(defgeneric compile-steering (source &key)
  (:documentation "Enabled directives as one system-prompt string. Empty → \"\"."))

(defgeneric apply-steering (turns source &key)
  (:documentation "TURNS with compiled steering merged into a :system turn."))

(defmethod list-directives ((source null) &key)
  (list-directives (%ensure-source source)))

(defmethod find-directive ((source null) name &key)
  (find-directive (%ensure-source source) name))

(defmethod compile-steering ((source null) &key)
  (compile-steering (%ensure-source source)))

(defmethod apply-steering (turns (source null) &key)
  (apply-steering turns (%ensure-source source)))

(defmethod find-directive (source name &key)
  (or (find name (list-directives source) :key #'steer-directive-name :test #'equal)
      (restart-case
          (error 'steer-unknown-directive
                 :name name
                 :message (format nil "unknown directive ~s" name))
        (use-value (value)
          :report "Use a supplied directive"
          value)
        (continue ()
          :report "Skip missing directive"
          nil))))

(defun %enabled-directives (source)
  (remove-if-not #'steer-directive-enabled-p (list-directives source)))

(defun %compile-directive (directive)
  (with-output-to-string (o)
    (format o "# ~a: ~a" (string-downcase (symbol-name (steer-directive-kind directive)))
            (steer-directive-name directive))
    (when (and (steer-directive-description directive)
               (plusp (length (steer-directive-description directive))))
      (format o "~%~a" (steer-directive-description directive)))
    (when (and (steer-directive-body directive)
               (plusp (length (steer-directive-body directive))))
      (format o "~%~a" (steer-directive-body directive)))))

(defmethod compile-steering (source &key)
  (let ((parts (mapcar #'%compile-directive (%enabled-directives source))))
    (if parts
        (format nil "~{~a~^~%~%~}" parts)
        "")))

(defun %merge-system (turns text)
  (let ((text (string-trim '(#\Space #\Tab #\Newline #\Return) (or text "")))
        (turns (llm-protocol:coerce-turns turns)))
    (if (zerop (length text))
        turns
        (let ((sys (find :system turns :key #'llm-protocol:llm-turn-role)))
          (if sys
              (cons (llm-protocol:system-turn
                     (let ((old (llm-protocol:turn-text sys)))
                       (if (plusp (length old))
                           (format nil "~a~%~%~a" old text)
                           text)))
                    (remove sys turns :test #'eq))
              (cons (llm-protocol:system-turn text) turns))))))

(defmethod apply-steering (turns source &key)
  (%merge-system turns (compile-steering source)))

(defclass in-memory-steering (steering-source)
  ((directives :initarg :directives :accessor steering-directives :initform nil)))

(defun make-in-memory-steering (&optional directives)
  (make-instance 'in-memory-steering
                 :directives (cond
                               ((null directives) nil)
                               ((steer-directive-p directives) (list directives))
                               ((listp directives) (copy-list directives))
                               (t (error 'steer-error
                                         :message (format nil "not directives: ~s"
                                                          directives))))))

(defun use-in-memory-steering (&optional directives)
  (setf *steering* (make-in-memory-steering directives)))

(defmethod list-directives ((source in-memory-steering) &key)
  (copy-list (steering-directives source)))

(defmethod register-directive ((source in-memory-steering) directive &key)
  (check-type directive steer-directive)
  (setf (steering-directives source)
        (append (remove (steer-directive-name directive)
                        (steering-directives source)
                        :key #'steer-directive-name :test #'equal)
                (list directive)))
  directive)

(defmethod unregister-directive ((source in-memory-steering) name &key)
  (let ((found (find-directive source name)))
    (when found
      (setf (steering-directives source)
            (remove (steer-directive-name found) (steering-directives source)
                    :key #'steer-directive-name :test #'equal)))
    source))

(defmethod list-directives ((source list) &key)
  (mapcan (lambda (item)
            (cond
              ((steer-directive-p item) (list item))
              ((steering-source-p item) (copy-list (list-directives item)))
              ((or (stringp item) (pathnamep item))
               (list (load-skill item)))
              (t (error 'steer-error
                        :message (format nil "not a steer directive: ~s" item)))))
          source))

(defmethod register-directive ((source list) directive &key)
  (declare (ignore source))
  (error 'steer-error :message "cannot register on a raw list — use in-memory-steering"))

(defun coerce-steering (x)
  (cond
    ((null x) nil)
    ((steering-source-p x) x)
    ((steer-directive-p x) (make-in-memory-steering (list x)))
    ((or (stringp x) (pathnamep x))
     (make-in-memory-steering (list (load-skill x))))
    ((listp x) (make-in-memory-steering (list-directives x)))
    (t (error 'steer-error :message (format nil "not steering: ~s" x)))))
