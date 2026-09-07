(defpackage #:steer-protocol
  (:use #:cl)
  (:nicknames #:stack-steer)
  (:export #:steer-error
           #:steer-error-message
           #:steer-missing-source
           #:steer-unknown-directive
           #:steer-unknown-directive-name
           #:steer-skill-not-found
           #:steer-skill-not-found-path

           #:steer-directive
           #:steer-directive-p
           #:make-steer-directive
           #:make-steer-rule
           #:make-steer-skill
           #:steer-directive-kind
           #:steer-directive-name
           #:steer-directive-description
           #:steer-directive-body
           #:steer-directive-path
           #:steer-directive-enabled-p
           #:steer-directive-extra

           #:steering-source
           #:steering-source-p
           #:*steering*

           #:list-directives
           #:find-directive
           #:register-directive
           #:unregister-directive
           #:compile-steering
           #:apply-steering
           #:parse-skill-markdown
           #:load-skill
           #:load-skills-from-directory

           #:in-memory-steering
           #:make-in-memory-steering
           #:use-in-memory-steering
           #:steering-directives
           #:coerce-steering))

(in-package #:steer-protocol)
