;;; mastodon-search.el --- Search functions for mastodon.el  -*- lexical-binding: t -*-

;; Copyright (C) 2017-2019 Marty Hiatt
;; Author: Marty Hiatt <mousebot@disroot.org>
;; Maintainer: Marty Hiatt <mousebot@disroot.org>
;; Homepage: https://codeberg.org/martianh/mastodon.el

;; This file is not part of GNU Emacs.

;; This file is part of mastodon.el.

;; mastodon.el is free software: you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; mastodon.el is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with mastodon.el.  If not, see <http://www.gnu.org/licenses/>.

;;; Commentary:

;; A basic search function for mastodon.el

;;; Code:
(require 'json)
(require 'mastodon-tl)
(require 'mastodon-widget)

(autoload 'mastodon-auth--access-token "mastodon-auth")
(autoload 'mastodon-http--api "mastodon-http")
(autoload 'mastodon-http--get-json "mastodon-http")
(autoload 'mastodon-http--get-search-json "mastodon-http")
(autoload 'mastodon-mode "mastodon")
(autoload 'mastodon-tl--as-string "mastodon-tl")
(autoload 'mastodon-tl--as-string "mastodon-tl")
(autoload 'mastodon-tl--render-text "mastodon-tl")
(autoload 'mastodon-tl--set-buffer-spec "mastodon-tl")
(autoload 'mastodon-tl--set-face "mastodon-tl")
(autoload 'mastodon-tl--timeline "mastodon-tl")
(autoload 'mastodon-tl--toot "mastodon-tl")
(autoload 'mastodon-tl--buffer-property "mastodon-tl")
(autoload 'mastodon-http--api-v2 "mastodon-http")

(defvar mastodon-toot--completion-style-for-mentions)
(defvar mastodon-instance-url)
(defvar mastodon-tl--link-keymap)
(defvar mastodon-tl--horiz-bar)

;; functions for completion of mentions in mastodon-toot

(defun mastodon-search--get-user-info-@ (account)
  "Get user handle, display name and account URL from ACCOUNT."
  (list (concat "@" (cdr (assoc 'acct account)))
        (cdr (assoc 'url account))
        (cdr (assoc 'display_name account))))

(defun mastodon-search--search-accounts-query (query)
  "Prompt for a search QUERY and return accounts synchronously.
Returns a nested list containing user handle, display name, and URL."
  (let* ((url (mastodon-http--api "accounts/search"))
         (response
          (mastodon-http--get-json
           url
           `(("q" . ,query) ;; NB: nil can break params (but works for me)
             ,(when (string= "following"
                           mastodon-toot--completion-style-for-mentions)
                '("following" . "true")))
           :silent)))
    (mapcar #'mastodon-search--get-user-info-@ response)))

;; functions for tags completion:

(defun mastodon-search--search-tags-query (query)
  "Return an alist containing tag strings plus their URLs.
QUERY is the string to search."
  (let* ((url (mastodon-http--api-v2 "search"))
         (params `(("q" . ,query) ("type" . "hashtags")))
         (response (mastodon-http--get-json url params :silent))
         (tags (alist-get 'hashtags response)))
    (mapcar #'mastodon-search--get-hashtag-info tags)))

;; trending tags

(defun mastodon-search-trending-tags ()
  "Display a list of tags trending on your instance."
  (interactive)
  (mastodon-search--view-trending "tags"
                                  #'mastodon-search--print-tags))

(defun mastodon-search-trending-statuses ()
  "Display a list of statuses trending on your instance."
  (interactive)
  (mastodon-search--view-trending "statuses"
                                  #'mastodon-tl--timeline))

(defun mastodon-search-trending-links ()
  "Display a list of links trending on your instance."
  (interactive)
  (mastodon-search--view-trending "links"
                                  #'mastodon-search--render-links))

(defun mastodon-search--render-links (links)
  "Render trending LINKS."
  (cl-loop for l in links
           do (mastodon-search--render-link l)))

(defun mastodon-search--render-link (link)
  "Render a trending LINK."
  (let-alist link
    (insert
     (propertize
      (mastodon-tl--render-text
       (concat "<a href=\"" .url "\">" .url "</a>\n" .title)
       link)
      'item-type 'link
      'item-json link
      'shr-url .url
      'byline t ;; nav
      'help-echo
      (substitute-command-keys
       "\\[`mastodon-search-load-link-posts'] to view a link's timeline"))
     ;; TODO: display card link author here
     "\n\n")))

(defun mastodon-search-load-link-posts ()
  "Load timeline of posts containing link at point."
  (interactive)
  (let* ((url (mastodon-tl--property 'shr-url)))
    (mastodon-tl--link-timeline url)))

(defun mastodon-search--view-trending (type print-fun)
  "Display a list of tags trending on your instance.
TYPE is a string, either tags, statuses, or links.
PRINT-FUN is the function used to print the data from the response."
  (let* ((url (mastodon-http--api (format "trends/%s" type)))
         ;; max for statuses = 40, for others = 20
         (limit (if (string= type "statuses")
                    '("limit" . "40")
                  '("limit" . "20")))
         (offset '(("offset" . "0")))
         (params (push limit offset))
         (data (mastodon-http--get-json url params))
         (buffer (get-buffer-create
                  (format "*mastodon-trending-%s*" type))))
    (with-mastodon-buffer buffer #'mastodon-mode nil
      (mastodon-tl--set-buffer-spec (buffer-name buffer)
                                    (format "trends/%s" type)
                                    print-fun nil params)
      (mastodon-search--insert-heading "trending" type)
      (funcall print-fun data)
      (unless (string= type "statuses")
        (goto-char (point-min))))))

;; functions for mastodon search

(defun mastodon-search--insert-heading (str &optional type)
  "Insert STR as a heading.
Optionally add string TYPE after HEADING."
  (insert
   (mastodon-search--format-heading str type)))

(defun mastodon-search--format-heading (str &optional type no-newline)
  "Format STR as a heading.
Optionally add string TYPE after HEADING.
NO-NEWLINE means don't add add a newline at end."
  (mastodon-tl--set-face
   (concat "\n " mastodon-tl--horiz-bar "\n "
           (upcase str) " "
           (when type (upcase type)) "\n"
           " " mastodon-tl--horiz-bar (unless no-newline "\n"))
   'success))

(defvar mastodon-search-types
  '("statuses" "accounts" "hashtags"))

(defun mastodon-search-query (query &optional type limit
                                     following account-id offset)
  "Prompt for a search QUERY and return accounts, statuses, and hashtags.
TYPE is a member of `mastodon-search-types'.
LIMIT is a number as string, up to 40, with 40 the default.
FOLLOWING means limit to accounts followed, for \"accounts\" type only.
A single prefix arg also sets FOLLOWING to true.
ACCOUNT-ID means limit search to that account, for \"statuses\" type only.
OFFSET is a number as string, means to skip that many results. It
is used for pagination."
  ;; TODO: handle no results
  (interactive "sSearch mastodon for: ")
  (let* ((url (mastodon-http--api-v2 "search"))
         (following (when (or following (equal current-prefix-arg '(4)))
                      "true"))
         (type (or type
                   (if (equal current-prefix-arg '(4))
                       "accounts" ; if FOLLOWING, must be "accounts"
                     (completing-read "Search type: "
                                      mastodon-search-types nil :match))))
         (limit (or limit "40"))
         (offset (or offset "0"))
         (buffer (format "*mastodon-search-%s-%s*" type query))
         (params `(("q" . ,query)
                   ,@(when type `(("type" . ,type)))
                   ,@(when limit `(("limit" . ,limit)))
                   ,@(when offset `(("offset" . ,offset)))
                   ,@(when following `(("following" . ,following)))
                   ,@(when account-id `(("account_id" . ,account-id)))))
         (response (mastodon-http--get-json url params))
         (items (alist-get (intern type) response)))
    (with-mastodon-buffer buffer #'mastodon-mode nil
      (mastodon-search-mode)
      (mastodon-search--insert-heading "search")
      (mastodon-widget--create
       "Results"
       '(accounts hashtags statuses)
       (intern type)
       (lambda (widget &rest _ignore)
         (let ((value (widget-value widget)))
           (mastodon-search-query query (symbol-name value)))))
      (insert "\n\n")
      (cond ((string= type "accounts")
             (mastodon-search--render-response items type buffer params
                                               'mastodon-views--insert-users-propertized-note
                                               'mastodon-views--insert-users-propertized-note))
            ((string= type "hashtags")
             (mastodon-search--render-response items type buffer params
                                               'mastodon-search--print-tags
                                               'mastodon-search--print-tags))
            ((string= type "statuses")
             (mastodon-search--render-response items type buffer params
                                               #'mastodon-tl--timeline
                                               #'mastodon-tl--timeline)))
      (goto-char (point-min))
      (message
       (substitute-command-keys
        "\\[mastodon-search-query-cycle] to cycle result types.")))))

(defun mastodon-search-insert-no-results (&optional thing)
  "Insert a no results message for object THING."
  (let ((thing (or thing "items")))
    (insert
     (propertize (format "Looks like search returned no %s." thing)
                 'face 'mastodon-toot-docs-face))))

(defun mastodon-search--render-response (data type buffer params
                                              insert-fun update-fun)
  "Call INSERT-FUN on DATA of result TYPE if non-nil.
BUFFER, PARAMS, and UPDATE-FUN are for `mastodon-tl--buffer-spec'."
  (if (not data)
      (mastodon-search-insert-no-results type)
    (funcall insert-fun data))
  (mastodon-tl--set-buffer-spec buffer "search"
                                update-fun nil params))

(defun mastodon-search--buf-type ()
  "Return search buffer type, a member of `mastodon-search-types'."
  ;; called in `mastodon-tl--get-buffer-type'
  (let* ((spec (mastodon-tl--buffer-property 'update-params)))
    (alist-get "type" spec nil nil #'string=)))

(defun mastodon-search-query-cycle ()
  "Cycle through search types: accounts, hashtags, and statuses."
  (interactive)
  (let* ((spec (mastodon-tl--buffer-property 'update-params))
         (type (alist-get "type" spec nil nil #'string=))
         (query (alist-get "q" spec nil nil #'string=)))
    (cond ((string= type "hashtags")
           (mastodon-search-query query "accounts"))
          ((string= type "accounts")
           (mastodon-search-query query "statuses"))
          ((string= type "statuses")
           (mastodon-search-query query "hashtags")))))

(defun mastodon-search-query-accounts-followed (query)
  "Run an accounts search QUERY, limited to your followers."
  (interactive "sSearch mastodon for: ")
  (mastodon-search-query query "accounts" :following))

(defun mastodon-search--insert-users-propertized (json &optional note)
  "Insert users list into the buffer.
JSON is the data from the server.
If NOTE is non-nil, include user's profile note. This is also
 called by `mastodon-tl--get-follow-suggestions' and
 `mastodon-profile--insert-follow-requests'."
  (cl-loop for acct in json
           do (insert (concat (mastodon-search--propertize-user acct note)
                              mastodon-tl--horiz-bar
                              "\n\n"))))

(defun mastodon-search--propertize-user (acct &optional note)
  "Propertize display string for ACCT, optionally including profile NOTE."
  (let* ((user (mastodon-search--get-user-info acct))
         (id (alist-get 'id acct)))
    (propertize
     (concat
      (propertize (car user)
                  'face 'mastodon-display-name-face
                  'byline t
                  'item-type 'user
                  'item-id id) ; for prev/next nav
      " : \n : "
      (propertize (concat "@" (cadr user))
                  'face 'mastodon-handle-face
                  'mouse-face 'highlight
		  'mastodon-tab-stop 'user-handle
		  'keymap mastodon-tl--link-keymap
                  'mastodon-handle (concat "@" (cadr user))
		  'help-echo (concat "Browse user profile of @" (cadr user)))
      " : \n"
      (when note
        (mastodon-tl--render-text (cadddr user) acct))
      "\n")
     'item-json acct))) ; for compat w other processing functions

(defun mastodon-search--print-tags (tags)
  "Print TAGS data as returned from a \"hashtags\" search query."
  (let ((tags-list (mapcar #'mastodon-search--get-hashtag-info tags)))
    (mastodon-search--print-tags-list tags-list)))

(defun mastodon-search--print-tags-list (tags-list)
  "Insert a propertized list of TAGS-LIST."
  (cl-loop for el in tags-list
           do (insert
               " : "
               (propertize (concat "#" (car el))
                           'face '(:box t)
                           'mouse-face 'highlight
                           'mastodon-tag (car el)
                           'mastodon-tab-stop 'hashtag
                           'item-type 'tag ; for next/prev nav
                           'byline t ; for next/prev nav
                           'help-echo (concat "Browse tag #" (car el))
                           'keymap mastodon-tl--link-keymap)
               " : \n\n")))

(defun mastodon-search--get-user-info (account)
  "Get user handle, display name, account URL and profile note from ACCOUNT."
  (list (mastodon-tl--display-or-uname account)
        (alist-get 'acct account)
        (alist-get 'url account)
        (alist-get 'note account)))

(defun mastodon-search--get-hashtag-info (tag)
  "Get hashtag name and URL from TAG."
  (list (alist-get 'name tag)
        (alist-get 'url tag)))

;; These functions are all unused!

;; (defun mastodon-search--get-status-info (status)
;;   "Get ID, timestamp, content, and spoiler from STATUS."
;;   (list (alist-get 'id status)
;;         (alist-get 'created_at status)
;;         (alist-get 'spoiler_text status)
;;         (alist-get 'content status)))

;; (defun mastodon-search--id-from-status (status)
;;   "Fetch the id from a STATUS returned by a search call to the server.
;; We use this to fetch the complete status from the server."
;;   (alist-get 'id status))

;; (defun mastodon-search--full-status-from-id (id)
;;   "Fetch the full status with id ID from the server.
;; This allows us to access the full account etc. details and to
;; render them properly."
;;   (let* ((url (mastodon-http--api (format "statuses/%s" id)))
;;          ;; (concat mastodon-instance-url "/api/v1/statuses/"
;;          ;; (mastodon-tl--as-string id)))
;;          (json (mastodon-http--get-json url)))
;;     json))

(defvar mastodon-search-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "C-c C-c") #'mastodon-search-query-cycle)
    map)
  "Keymap for `mastodon-search-mode'.")

(define-minor-mode mastodon-search-mode
  "Toggle mastodon search minor mode.
This minor mode is used for mastodon search pages to adds a keybinding."
  :init-value nil
  :lighter " Search"
  :keymap mastodon-search-mode-map
  :group 'mastodon
  :global nil)

(provide 'mastodon-search)
;;; mastodon-search.el ends here
