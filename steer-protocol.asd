(defsystem "steer-protocol"
  :version "0.4.0"
  :description "CLOS rules/skills steering protocol for cl-stack (not A2A agent-skill)"
  :author "egao1980"
  :license "MIT"
  :depends-on ("llm-protocol" (:version "yaml-protocol" "0.2.1"))
  :serial t
  :pathname "src"
  :components ((:file "package")
               (:file "conditions")
               (:file "protocol")
               (:file "skill")
               (:file "store")
               (:file "instructions")
               (:file "prompt"))
  :in-order-to ((test-op (test-op "steer-protocol/tests"))))

(defsystem "steer-protocol/tests"
  :depends-on ("steer-protocol" "rove")
  :pathname "tests"
  :serial t
  :components ((:file "package")
               (:file "protocol-test")
               (:file "restarts-test")
               (:file "skill-test")
               (:file "frontmatter-test")
               (:file "store-test")
               (:file "instructions-test")
               (:file "prompt-test"))
  :perform (test-op (o c)
             (unless (symbol-call :rove :run c)
               (error "tests failed for ~A" (component-name c)))))
