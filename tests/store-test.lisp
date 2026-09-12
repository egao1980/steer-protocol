(in-package #:steer-protocol/tests)

(defun %tmpdir (prefix)
  (let ((root (uiop:ensure-directory-pathname
               (merge-pathnames (format nil "~a-~a/" prefix (random 100000000))
                                (uiop:temporary-directory)))))
    (ensure-directories-exist root)
    root))

(defun %make-skill (name body &optional description)
  (steer-protocol:make-steer-skill name :body body :description description))

(deftest file-skill-store-save-versions-rollback
  (let ((root (%tmpdir "steer-file")))
    (unwind-protect
         (let* ((store (steer-protocol:make-file-skill-store root))
                (v1 (steer-protocol:save-skill-version
                     store (%make-skill "review" "first body" "v1")
                     :provenance '(:eval-run "r1")))
                (v2 (steer-protocol:save-skill-version
                     store (%make-skill "review" "second body" "v2")
                     :provenance '(:eval-run "r2" :improvement-cycle "c1")))
                (vers (steer-protocol:skill-versions store "review")))
           (ok (steer-protocol:skill-version-p v1))
           (ok (steer-protocol:skill-version-p v2))
           (ok (equal "1" (steer-protocol:skill-version-id v1)))
           (ok (equal "2" (steer-protocol:skill-version-id v2)))
           (ok (equal '(:eval-run "r2" :improvement-cycle "c1")
                      (steer-protocol:skill-version-provenance v2)))
           (ok (= 2 (length vers)))
           (ok (equal "2" (steer-protocol:skill-version-id (first vers))))
           (ok (search "second body"
                       (steer-protocol:steer-directive-body
                        (steer-protocol:load-skill-version store "review" "2"))))
           (ok (search "first body"
                       (steer-protocol:steer-directive-body
                        (steer-protocol:load-skill-version store "review" v1))))
           (let ((rolled (steer-protocol:rollback-skill store "review" "1")))
             (ok (search "first body"
                         (steer-protocol:steer-directive-body rolled)))
             (ok (search "first body"
                         (uiop:read-file-string
                          (merge-pathnames "review/SKILL.md" root))))))
      (uiop:delete-directory-tree root :validate t :if-does-not-exist :ignore))))

(deftest file-skill-store-unknown-version
  (let ((root (%tmpdir "steer-file-miss")))
    (unwind-protect
         (let ((store (steer-protocol:make-file-skill-store root)))
           (steer-protocol:save-skill-version
            store (%make-skill "x" "only"))
           (ok (signals (steer-protocol:load-skill-version store "x" "99")
                        'steer-protocol:steer-unknown-version)))
      (uiop:delete-directory-tree root :validate t :if-does-not-exist :ignore))))

(defun %init-git-repo (root)
  (uiop:run-program '("git" "init")
                    :directory root
                    :output :string
                    :error-output :string)
  (uiop:run-program '("git" "-c" "user.name=steer-protocol"
                      "-c" "user.email=steer@localhost"
                      "config" "commit.gpgsign" "false")
                    :directory root
                    :ignore-error-status t
                    :output :string
                    :error-output :string)
  root)

(deftest git-skill-store-save-versions-rollback
  (if (not (steer-protocol:git-available-p))
      (skip "git not available")
      (let ((root (%tmpdir "steer-git")))
        (unwind-protect
             (progn
               (%init-git-repo root)
               (let* ((store (steer-protocol:make-git-skill-store root))
                      (v1 (steer-protocol:save-skill-version
                           store (%make-skill "review" "git first")
                           :provenance '(:eval-run "g1")))
                      (v2 (steer-protocol:save-skill-version
                           store (%make-skill "review" "git second")
                           :provenance '(:eval-run "g2")))
                      (vers (steer-protocol:skill-versions store "review")))
                 (ok (plusp (length (steer-protocol:skill-version-id v1))))
                 (ok (plusp (length (steer-protocol:skill-version-id v2))))
                 (ok (not (equal (steer-protocol:skill-version-id v1)
                                 (steer-protocol:skill-version-id v2))))
                 (ok (= 2 (length vers)))
                 (ok (equal (steer-protocol:skill-version-id v2)
                            (steer-protocol:skill-version-id (first vers))))
                 (ok (equal '(:eval-run "g2")
                            (steer-protocol:skill-version-provenance (first vers))))
                 (ok (search "git first"
                             (steer-protocol:steer-directive-body
                              (steer-protocol:load-skill-version
                               store "review" v1))))
                 (let ((rolled (steer-protocol:rollback-skill
                                store "review" v1)))
                   (ok (search "git first"
                               (steer-protocol:steer-directive-body rolled))))))
          (uiop:delete-directory-tree root :validate t
                                      :if-does-not-exist :ignore)))))
