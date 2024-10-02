;;; mastodon-transient.el --- transient menus for mastodon.el  -*- lexical-binding: t; -*-

;; Copyright (C) 2024  martian hiatus

;; Author: martian hiatus <martianhiatus@riseup.net>
;; Keywords: convenience

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <https://www.gnu.org/licenses/>.

;;; Commentary:

;; 

;;; Code:

(require 'tp)

(defun mastodon-transient-parse-source-key (key)
  "Parse mastodon source KEY.
If KEY needs to be source[key], format like so, else just return
the inner key part."
  (let* ((split (split-string key "[][]"))
         (array-key (cadr split)))
    (if (or (= 1 (length split)) ;; no split
            (member array-key '("privacy" "sensitive" "language")))
        key
      array-key)))

(defun mastodon-transient-parse-source-keys (alist)
  "Parse ALIST containing source[key] keys."
  (cl-loop for a in alist
           collect (cons (mastodon-transient-parse-source-key (car a))
                         (cdr a))))

;; FIXME: PATCHing source vals as JSON request body doesn't work!
;; existing `mastodon-profile--update-preference' doesn't use it! it just uses
;; query params! strange thing is it works for non-source params
(transient-define-suffix mastodon-user-settings-update (&optional args)
  "Update current user settings on the server."
  :transient 'transient--do-exit
  ;; interactive receives args from the prefix:
  (interactive (list (transient-args 'mastodon-user-settings)))
  (let* ((alist (tp-transient-to-alist args))
         (only-changed (tp-only-changed-args alist))
         (arrays (tp-dots-to-arrays only-changed))
         (parsed-source (mastodon-transient-parse-source-keys arrays))
         (endpoint "accounts/update_credentials")
         (url (mastodon-http--api endpoint))
         (resp (mastodon-http--patch url parsed-source))) ; :json)))
    (mastodon-http--triage
     resp
     (lambda (_)
       (message "Settings updated!\n%s" parsed-source)))))

(defun mastodon-transient-get-creds ()
  "Fetch account data."
  (mastodon-http--get-json
   (mastodon-http--api "accounts/verify_credentials")
   nil :silent))

(transient-define-prefix mastodon-user-settings ()
  "A transient for setting current user settings."
  :value (lambda () (tp-return-data
                     #'mastodon-transient-get-creds))
  [:description
   ;; '()
   (lambda ()
     "Settings")
   ;;   (format "User settings for %s" mastodon-active-user))
   (:info
    "Note: use the empty string (\"\") to remove a value from an option.")
   ]
  ;; strings
  ["Account info"
   ("n" "display name" "display_name=" :class tp-option-str)]
  ;; "choice" booleans (so we can PATCH :json-false explicitly):
  ["Account options"
   ("l" "locked" "locked=" :class tp-choice-bool)
   ("b" "bot" "bot=" :class tp-choice-bool)
   ("d"  "discoverable" "discoverable=" :class tp-choice-bool)

   ("c" "hide follower/following lists" "source.hide_collections=" :class tp-choice-bool)
   ("i" "indexable" "source.indexable=" :class tp-choice-bool)]
  ["Tooting options"
   ("p" "default privacy" "source.privacy=" :class tp-option
    :choices (lambda () mastodon-toot-visibility-settings-list))
   ("s" "mark sensitive" "source.sensitive=" :class tp-choice-bool)
   ("g" "default language" "source.language=" :class tp-option
    :choices (lambda () mastodon-iso-639-regional))]
  ["Update"
   ("C-c C-c" "Save settings" mastodon-user-settings-update)
   ;; ("C-c C-k" :info "to revert all changes")
   ]
  (interactive)
  (if (not mastodon-active-user)
      (user-error "User not set")
    (transient-setup 'mastodon-user-settings)))

(provide 'mastodon-transient)
;;; mastodon-transient.el ends here
