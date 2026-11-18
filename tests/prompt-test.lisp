(in-package #:steer-protocol/tests)

(deftest-parametrize model-family-from-designator
    ((designator family)
     ("claude-opus-5-5" :anthropic)
     ("us.anthropic.claude-sonnet" :anthropic)
     ("gpt-5" :openai)
     ("o3-mini" :openai)
     ("llama-3" nil)
     (:openai :openai)
     (nil nil))
  (ok (eq family (steer-protocol:model-family designator))))

(deftest prompt-variant-dispatch
  (ok (typep (steer-protocol:prompt-variant-for "claude-x")
             'steer-protocol:anthropic-prompt-variant))
  (ok (typep (steer-protocol:prompt-variant-for :openai)
             'steer-protocol:openai-prompt-variant))
  (ok (eq :default (steer-protocol:prompt-variant-name
                    (steer-protocol:prompt-variant-for "mistral-large"))))
  (ok (eq :default (steer-protocol:prompt-variant-name
                    (steer-protocol:prompt-variant-for nil))))
  (let ((v (make-instance 'steer-protocol:prompt-variant :preamble "P")))
    (ok (eq v (steer-protocol:prompt-variant-for v))))
  (ok (eq :default (steer-protocol:prompt-variant-name
                    (steer-protocol:prompt-variant-for
                     (llm-protocol:make-mock-llm-backend))))))

(deftest build-system-prompt-lists-present-tools-only
  (let ((text (steer-protocol:build-system-prompt
               :tools (list "read" (llm-protocol:make-llm-tool :name "bash")
                            "mystery_tool")
               :model "claude-opus")))
    (ok (search "# Tools" text))
    (ok (search "- read:" text))
    (ok (search "- bash:" text))
    (ng (search "mystery_tool" text))
    (ng (search "grep" text))
    (ok (search (steer-protocol:prompt-variant-preamble
                 (steer-protocol:prompt-variant-for :anthropic))
                text))))

(deftest build-system-prompt-no-tools-and-extra
  (let ((text (steer-protocol:build-system-prompt :preamble "Hi." :extra "Bye.")))
    (ng (search "# Tools" text))
    (ok (equal (format nil "Hi.~%~%Bye.") text))))

(defclass terse-variant (steer-protocol:prompt-variant) ()
  (:default-initargs :name :terse :preamble "Terse."))

(defmethod steer-protocol:prompt-variant-for-family ((family (eql :terse-test)))
  (make-instance 'terse-variant))

(defmethod steer-protocol:tool-guidance ((v terse-variant) (name string))
  (if (string-equal name "read") "Read." nil))

(deftest custom-variant-via-gf
  (let ((text (steer-protocol:build-system-prompt :tools '("read" "bash")
                                                  :model :terse-test)))
    (ok (search "Terse." text))
    (ok (search "- read: Read." text))
    (ng (search "bash" text))))

(deftest register-tool-guidance-adds
  (let ((steer-protocol:*tool-guidance* (make-hash-table :test #'equalp)))
    (steer-protocol:register-tool-guidance "lisp_eval" "Eval in the image.")
    (ok (search "- lisp_eval: Eval in the image."
                (steer-protocol:build-system-prompt :tools '(:lisp_eval))))))
