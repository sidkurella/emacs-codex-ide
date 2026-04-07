;;; codex-ide-mcp-elicitation-tests.el --- Tests for codex-ide MCP elicitation -*- lexical-binding: t; -*-

;;; Commentary:

;; Tests for MCP elicitation helpers and codex-ide integration.

;;; Code:

(require 'ert)
(require 'json)
(require 'codex-ide-test-fixtures)
(require 'codex-ide)

(ert-deftest codex-ide-mcp-elicitation-capabilities-include-form-and-url ()
  (should
   (equal (codex-ide-mcp-elicitation-capabilities)
          '((elicitation . ((form . ())
                            (url . ())))))))

(ert-deftest codex-ide-mcp-elicitation-form-request-collects-supported-values ()
  (let ((completions '("submit" "false" "Option B"))
        (inputs '("Ada" "7")))
    (cl-letf (((symbol-function 'completing-read)
               (lambda (&rest _)
                 (pop completions)))
              ((symbol-function 'read-from-minibuffer)
               (lambda (&rest _)
                 (pop inputs))))
      (should
       (equal
        (codex-ide-mcp-elicitation-handle-request
         '((message . "Need settings")
           (requestedSchema
            . ((type . "object")
               (properties
                . ((name . ((type . "string")
                            (title . "Name")))
                   (count . ((type . "integer")
                             (title . "Count")))
                   (enabled . ((type . "boolean")
                               (title . "Enabled")))
                   (choice . ((type . "string")
                              (title . "Choice")
                              (enum . ("a" "b"))
                              (enumNames . ("Option A" "Option B"))))))
               (required . ("name" "count" "enabled" "choice"))))))
        '((action . "accept")
          (content . ((name . "Ada")
                      (count . 7)
                      (enabled . :json-false)
                      (choice . "b")))))))))

(ert-deftest codex-ide-mcp-elicitation-normalizes-nested-request-payload ()
  (let ((completions '("submit"))
        (inputs '("Ada")))
    (cl-letf (((symbol-function 'completing-read)
               (lambda (&rest _)
                 (pop completions)))
              ((symbol-function 'read-from-minibuffer)
               (lambda (&rest _)
                 (pop inputs))))
      (should
       (equal
        (codex-ide-mcp-elicitation-handle-request
         '((request
            . ((message . "Need settings")
               (requestedSchema
                . ((type . "object")
                   (properties
                    . ((name . ((type . "string")
                                (title . "Name")))))
                   (required . ("name"))))))))
        '((action . "accept")
          (content . ((name . "Ada")))))))))

(ert-deftest codex-ide-mcp-elicitation-url-request-can-open-browser ()
  (let ((opened-url nil))
    (cl-letf (((symbol-function 'completing-read)
               (lambda (&rest _) "open and continue"))
              ((symbol-function 'browse-url)
               (lambda (url &rest _)
                 (setq opened-url url))))
      (should
       (equal
        (codex-ide-mcp-elicitation-handle-request
         '((mode . "url")
           (message . "Authenticate")
           (url . "https://example.com/auth")))
        '((action . "accept"))))
      (should (equal opened-url "https://example.com/auth")))))

(ert-deftest codex-ide-initialize-session-advertises-elicitation-capability ()
  (let ((project-dir (codex-ide-test--make-temp-project))
        (captured-params nil))
    (codex-ide-test-with-fixture project-dir
      (codex-ide-test-with-fake-processes
        (let ((session (codex-ide--create-process-session)))
          (cl-letf (((symbol-function 'codex-ide--request-sync)
                     (lambda (_session method params)
                       (should (equal method "initialize"))
                       (setq captured-params params)
                       '((ok . t)))))
            (codex-ide--initialize-session session)))
        (should (equal (alist-get 'experimentalApi
                                  (alist-get 'capabilities captured-params))
                       t))
        (should (equal (alist-get 'form
                                  (alist-get 'elicitation
                                             (alist-get 'capabilities captured-params)))
                       '()))
        (should (equal (alist-get 'url
                                  (alist-get 'elicitation
                                             (alist-get 'capabilities captured-params)))
                       '()))))))

(ert-deftest codex-ide-handle-server-request-dispatches-elicitation-create ()
  (let ((project-dir (codex-ide-test--make-temp-project)))
    (codex-ide-test-with-fixture project-dir
      (codex-ide-test-with-fake-processes
        (let* ((session (codex-ide--create-process-session))
               (process (codex-ide-session-process session)))
          (cl-letf (((symbol-function 'run-at-time)
                     (lambda (_time _repeat fn &rest args)
                       (apply fn args)
                       nil))
                    ((symbol-function 'codex-ide-mcp-elicitation-handle-request)
                     (lambda (_params)
                       '((action . "accept")
                         (content . ((name . "Ada")))))))
            (codex-ide--handle-server-request
             session
             '((id . 17)
               (method . "elicitation/create")
               (params . ((message . "Need your name")))))
            (should
             (equal
              (mapcar (lambda (payload)
                        (json-parse-string payload
                                           :object-type 'alist
                                           :array-type 'list
                                           :null-object nil
                                           :false-object :json-false))
                      (codex-ide-test-process-sent-strings process))
              '(((id . 17)
                 (result . ((action . "accept")
                            (content . ((name . "Ada")))))))))
            (with-current-buffer (codex-ide-session-buffer session)
              (should (string-match-p "MCP elicitation (form): Need your name"
                                      (buffer-string))))))))))

(ert-deftest codex-ide-handle-server-request-dispatches-mcpserver-elicitation-request ()
  (let ((project-dir (codex-ide-test--make-temp-project)))
    (codex-ide-test-with-fixture project-dir
      (codex-ide-test-with-fake-processes
        (let* ((session (codex-ide--create-process-session))
               (process (codex-ide-session-process session)))
          (cl-letf (((symbol-function 'run-at-time)
                     (lambda (_time _repeat fn &rest args)
                       (apply fn args)
                       nil))
                    ((symbol-function 'codex-ide-mcp-elicitation-handle-request)
                     (lambda (_params)
                       '((action . "accept")
                         (content . ((choice . "yes")))))))
            (codex-ide--handle-server-request
             session
             '((id . 18)
               (method . "mcpServer/elicitation/request")
               (params . ((request . ((message . "Need a choice")))))))
            (should
             (equal
              (mapcar (lambda (payload)
                        (json-parse-string payload
                                           :object-type 'alist
                                           :array-type 'list
                                           :null-object nil
                                           :false-object :json-false))
                      (codex-ide-test-process-sent-strings process))
              '(((id . 18)
                 (result . ((action . "accept")
                            (content . ((choice . "yes")))))))))
            (with-current-buffer (codex-ide-session-buffer session)
              (should (string-match-p
                       (regexp-quote "MCP elicitation (form): Need a choice")
                                      (buffer-string))))))))))

(provide 'codex-ide-mcp-elicitation-tests)

;;; codex-ide-mcp-elicitation-tests.el ends here
