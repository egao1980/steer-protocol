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
           #:steer-frontmatter-error
           #:steer-frontmatter-error-path
           #:steer-frontmatter-error-cause

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
           #:skill-frontmatter
           #:skill-paths
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

           #:steer-instruction-unreadable
           #:steer-instruction-unreadable-path
           #:steer-instruction-unreadable-cause
           #:*default-instruction-names*
           #:instruction-discovery
           #:instruction-discovery-p
           #:make-instruction-discovery
           #:coerce-instruction-discovery
           #:copy-instruction-discovery
           #:instruction-discovery-root
           #:instruction-discovery-names
           #:instruction-discovery-per-directory
           #:instruction-discovery-include-root-p
           #:instruction-candidates
           #:discover-instructions
           #:instruction-injected-p
           #:mark-instructions-injected
           #:forget-instructions
           #:instruction-content-hash
           #:compile-instructions

           #:prompt-variant
           #:prompt-variant-p
           #:anthropic-prompt-variant
           #:openai-prompt-variant
           #:prompt-variant-name
           #:prompt-variant-preamble
           #:prompt-variant-for
           #:prompt-variant-for-family
           #:model-family
           #:*tool-guidance*
           #:register-tool-guidance
           #:tool-guidance
           #:render-system-prompt
           #:build-system-prompt

           #:in-memory-steering
           #:make-in-memory-steering
           #:use-in-memory-steering
           #:steering-directives
           #:coerce-steering))

(in-package #:steer-protocol)
