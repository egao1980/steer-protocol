(in-package #:steer-protocol/tests)

(deftest missing-source-use-value
  (let* ((src (steer-protocol:make-in-memory-steering
               (steer-protocol:make-steer-rule "r" :body "ok")))
         (steer-protocol:*steering* nil)
         (text nil))
    (handler-bind ((steer-protocol:steer-missing-source
                    (lambda (c)
                      (use-value src c))))
      (setf text (steer-protocol:compile-steering nil)))
    (ok (search "ok" text))))

(deftest unknown-directive-signals
  (let ((src (steer-protocol:make-in-memory-steering)))
    (ok (signals (steer-protocol:find-directive src "nope")
                 'steer-protocol:steer-unknown-directive))))

(deftest unknown-directive-continue
  (let ((src (steer-protocol:make-in-memory-steering))
        (got :unset))
    (handler-bind ((steer-protocol:steer-unknown-directive
                    (lambda (c)
                      (declare (ignore c))
                      (invoke-restart 'continue))))
      (setf got (steer-protocol:find-directive src "nope")))
    (ok (null got))))

(deftest unknown-directive-use-value
  (let ((src (steer-protocol:make-in-memory-steering))
        (d (steer-protocol:make-steer-rule "x" :body "y"))
        (got nil))
    (handler-bind ((steer-protocol:steer-unknown-directive
                    (lambda (c)
                      (use-value d c))))
      (setf got (steer-protocol:find-directive src "x")))
    (ok (eq d got))))

(deftest skill-not-found-signals
  (ok (signals (steer-protocol:load-skill "/no/such/SKILL.md")
               'steer-protocol:steer-skill-not-found)))

(deftest skill-not-found-use-value
  (let ((d (steer-protocol:make-steer-skill "fallback" :body "ok"))
        (got nil))
    (handler-bind ((steer-protocol:steer-skill-not-found
                    (lambda (c)
                      (use-value d c))))
      (setf got (steer-protocol:load-skill "/no/such/SKILL.md")))
    (ok (eq d got))))
