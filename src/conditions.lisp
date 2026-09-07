(in-package #:steer-protocol)

(define-condition steer-error (error)
  ((message :initarg :message :reader steer-error-message :initform nil))
  (:report (lambda (c s)
             (format s "steer error~@[: ~a~]" (steer-error-message c)))))

(define-condition steer-missing-source (steer-error)
  ()
  (:report (lambda (c s)
             (format s "steering source missing~@[: ~a~]"
                     (steer-error-message c)))))

(define-condition steer-unknown-directive (steer-error)
  ((name :initarg :name :reader steer-unknown-directive-name :initform nil))
  (:report (lambda (c s)
             (format s "unknown steer directive ~s~@[: ~a~]"
                     (steer-unknown-directive-name c)
                     (steer-error-message c)))))

(define-condition steer-skill-not-found (steer-error)
  ((path :initarg :path :reader steer-skill-not-found-path :initform nil))
  (:report (lambda (c s)
             (format s "SKILL.md not found: ~s~@[: ~a~]"
                     (steer-skill-not-found-path c)
                     (steer-error-message c)))))
