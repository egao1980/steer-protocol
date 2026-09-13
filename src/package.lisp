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
           #:steer-skill-store-error
           #:steer-skill-store-error-store
           #:steer-skill-store-error-name
           #:steer-unknown-version
           #:steer-unknown-version-id

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
           #:serialize-skill-markdown
           #:skill-tools
           #:skill-tool-fn
           #:register-skill-tool-fn

           #:skill-store
           #:skill-store-p
           #:skill-store-root
           #:file-skill-store
           #:make-file-skill-store
           #:git-skill-store
           #:make-git-skill-store
           #:git-available-p
           #:save-skill-version
           #:skill-versions
           #:rollback-skill
           #:load-skill-version

           #:skill-version
           #:skill-version-p
           #:make-skill-version
           #:skill-version-id
           #:skill-version-timestamp
           #:skill-version-provenance
           #:skill-version-name

           #:in-memory-steering
           #:make-in-memory-steering
           #:use-in-memory-steering
           #:steering-directives
           #:coerce-steering))

(in-package #:steer-protocol)
