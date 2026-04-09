;;; codex-ide-session-buffer-list-tests.el --- Tests for session buffer list -*- lexical-binding: t; -*-

;;; Commentary:

;; Tests for `codex-ide-session-buffer-list'.

;;; Code:

(require 'ert)
(require 'codex-ide-test-fixtures)
(require 'codex-ide)
(require 'codex-ide-session-buffer-list)

(ert-deftest codex-ide-session-buffer-list-renders-live-sessions-across-workspaces ()
  (let* ((root-dir (codex-ide-test--make-temp-project))
         (project-a (expand-file-name "alpha" root-dir))
         (project-b (expand-file-name "beta" root-dir)))
    (make-directory project-a t)
    (make-directory project-b t)
    (codex-ide-test-with-fixture root-dir
      (codex-ide-test-with-fake-processes
        (let ((session-a nil)
              (session-b nil))
          (let ((default-directory project-a))
            (setq session-a (codex-ide--create-process-session)))
          (let ((default-directory project-b))
            (setq session-b (codex-ide--create-process-session)))
          (setf (codex-ide-session-thread-id session-a) "thread-alpha"
                (codex-ide-session-thread-id session-b) "thread-beta"
                (codex-ide-session-status session-a) "idle"
                (codex-ide-session-status session-b) "running")
          (codex-ide-session-buffer-list)
          (with-current-buffer "*Codex Session Buffers*"
            (should (derived-mode-p 'codex-ide-session-buffer-list-mode))
            (should hl-line-mode)
            (should (eq hl-line-face 'codex-ide-session-list-current-row-face))
            (let* ((entries (funcall tabulated-list-entries))
                   (first-row (cadr (car entries))))
              (should (eq (get-text-property 0 'face (aref first-row 0))
                          'codex-ide-session-list-primary-face))
              (should (eq (get-text-property 0 'face (aref first-row 1))
                          'codex-ide-session-list-secondary-face))
              (should (eq (get-text-property 0 'face (aref first-row 2))
                          'codex-ide-session-list-id-face))
              (should (eq (get-text-property 0 'face (aref first-row 3))
                          'codex-ide-session-list-status-face)))
            (should (string-match-p (regexp-quote (buffer-name (codex-ide-session-buffer session-a)))
                                    (buffer-string)))
            (should (string-match-p (regexp-quote (abbreviate-file-name project-a))
                                    (buffer-string)))
            (should (string-match-p (regexp-quote (buffer-name (codex-ide-session-buffer session-b)))
                                    (buffer-string)))
            (should (string-match-p (regexp-quote (abbreviate-file-name project-b))
                                    (buffer-string)))))))))

(ert-deftest codex-ide-session-buffer-list-delete-buffer-kills-session-at-point ()
  (let* ((root-dir (codex-ide-test--make-temp-project))
         (project-a (expand-file-name "alpha" root-dir))
         (project-b (expand-file-name "beta" root-dir)))
    (make-directory project-a t)
    (make-directory project-b t)
    (codex-ide-test-with-fixture root-dir
      (codex-ide-test-with-fake-processes
        (let ((session-a nil)
              (session-b nil)
              (deleted-session nil)
              (deleted-buffer nil)
              (deleted-buffer-name nil))
          (let ((default-directory project-a))
            (setq session-a (codex-ide--create-process-session)))
          (let ((default-directory project-b))
            (setq session-b (codex-ide--create-process-session)))
          (codex-ide-session-buffer-list)
          (with-current-buffer "*Codex Session Buffers*"
            (goto-char (point-min))
            (forward-line 1)
            (setq deleted-session (tabulated-list-get-id)
                  deleted-buffer (codex-ide-session-buffer deleted-session)
                  deleted-buffer-name (buffer-name deleted-buffer))
            (cl-letf (((symbol-function 'y-or-n-p)
                       (lambda (prompt)
                         (should (string-match-p
                                  (regexp-quote deleted-buffer-name)
                                  prompt))
                         t)))
              (codex-ide-session-buffer-list-delete-buffer))
            (should-not (buffer-live-p deleted-buffer))
            (should (= (length codex-ide--sessions) 1))
            (should-not (memq deleted-session codex-ide--sessions))
            (should (or (memq session-a codex-ide--sessions)
                        (memq session-b codex-ide--sessions)))
            (should-not (string-match-p (regexp-quote deleted-buffer-name)
                                        (buffer-string)))))))))

(ert-deftest codex-ide-session-buffer-list-delete-buffer-aborts-when-not-confirmed ()
  (let* ((root-dir (codex-ide-test--make-temp-project))
         (project-dir (expand-file-name "alpha" root-dir)))
    (make-directory project-dir t)
    (codex-ide-test-with-fixture root-dir
      (codex-ide-test-with-fake-processes
        (let ((session nil)
              (buffer nil))
          (let ((default-directory project-dir))
            (setq session (codex-ide--create-process-session)))
          (setq buffer (codex-ide-session-buffer session))
          (codex-ide-session-buffer-list)
          (with-current-buffer "*Codex Session Buffers*"
            (goto-char (point-min))
            (search-forward (buffer-name buffer))
            (beginning-of-line)
            (cl-letf (((symbol-function 'y-or-n-p)
                       (lambda (_prompt) nil)))
              (codex-ide-session-buffer-list-delete-buffer))
            (should (buffer-live-p buffer))
            (should (memq session codex-ide--sessions))
            (should (string-match-p (regexp-quote (buffer-name buffer))
                                    (buffer-string)))))))))

(ert-deftest codex-ide-session-buffer-list-redisplay-refreshes-visible-rows ()
  (let* ((root-dir (codex-ide-test--make-temp-project))
         (project-a (expand-file-name "alpha" root-dir))
         (project-b (expand-file-name "beta" root-dir))
         (buffer-a-name nil)
         (buffer-b-name nil))
    (make-directory project-a t)
    (make-directory project-b t)
    (codex-ide-test-with-fixture root-dir
      (codex-ide-test-with-fake-processes
        (let ((session-a nil)
              (session-b nil))
          (let ((default-directory project-a))
            (setq session-a (codex-ide--create-process-session)))
          (setq buffer-a-name (buffer-name (codex-ide-session-buffer session-a)))
          (codex-ide-session-buffer-list)
          (let ((default-directory project-b))
            (setq session-b (codex-ide--create-process-session)))
          (setq buffer-b-name (buffer-name (codex-ide-session-buffer session-b)))
          (with-current-buffer "*Codex Session Buffers*"
            (should (eq (lookup-key codex-ide-session-buffer-list-mode-map (kbd "l"))
                        #'codex-ide-session-buffer-list-redisplay))
            (should-not (string-match-p (regexp-quote buffer-b-name)
                                        (buffer-string)))
            (call-interactively #'codex-ide-session-buffer-list-redisplay)
            (should (string-match-p (regexp-quote buffer-a-name)
                                    (buffer-string)))
            (should (string-match-p (regexp-quote buffer-b-name)
                                    (buffer-string)))))))))

(provide 'codex-ide-session-buffer-list-tests)

;;; codex-ide-session-buffer-list-tests.el ends here
