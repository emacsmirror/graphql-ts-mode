;;; graphql-ts-mode.el --- Tree-sitter support for GraphQL  -*- lexical-binding: t; -*-

;; Copyright (C) 2023 Joram Schrijver <i@joram.io>

;; Author: Joram Schrijver <i@joram.io>
;; Maintainer: Joram Schrijver <i@joram.io>
;; Created: September 2023
;; Version: 0.1.0
;; License: GPL-3.0-or-later
;; Package-Requires: ((emacs "29.1"))
;; Keywords: languages graphql tree-sitter
;; URL: https://sr.ht/~joram/graphql-ts-mode/

;; This program is free software: you can redistribute it and/or modify
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

;; This is a major mode for editing GraphQL files, implementing highlighting
;; and indentation.

;;; Code:

(require 'treesit)
(eval-when-compile
  (require 'rx)
  (require 'cl-lib))

(defgroup graphql-ts nil
  "Major mode for editing GraphQL code."
  :prefix "graphql-ts-"
  :group 'languages)

(defcustom graphql-ts-indent-offset 2
  "Number of spaces for each indentation step in `graphql-ts-mode'."
  :type 'integer
  :safe 'integerp
  :group 'graphql-ts)

(defvar graphql-ts-mode--keywords
  '("schema" "type" "query" "mutation" "subscription" "extend" "fragment" "on"
    "input" "enum" "scalar" "union" "interface" "implements" "directive"
    "repeatable")
  "Keywords to highlight in `graphql-ts-mode'.")

(defvar graphql-ts-mode--syntax-table
  (let ((table (make-syntax-table)))

    (modify-syntax-entry ?: "." table)
    (modify-syntax-entry ?. "." table)
    (modify-syntax-entry ?& "." table)
    (modify-syntax-entry ?| "." table)
    (modify-syntax-entry ?, " " table)
    (modify-syntax-entry ?\\ "\\" table)

    (modify-syntax-entry ?# "<" table)
    (modify-syntax-entry ?\n ">" table)

    (modify-syntax-entry ?\( "()" table)
    (modify-syntax-entry ?\) ")(" table)
    (modify-syntax-entry ?\{ "(}" table)
    (modify-syntax-entry ?\} "){" table)
    (modify-syntax-entry ?\[ "(]" table)
    (modify-syntax-entry ?\] ")[" table)

    table)
  "Syntax table for `graphql-ts-mode'.")

(defvar graphql-ts-mode--indent-rules
  (let ((offset graphql-ts-indent-offset))
    `((graphql
       ((parent-is "source_file") column-0 0)
       ((parent-is "document") column-0 0)
       ((node-is ")") parent-bol 0)
       ((node-is "}") parent-bol 0)
       ((node-is "]") parent-bol 0)
       ((node-is "root_operation_type_definition") parent-bol ,offset)
       ((parent-is "fields_definition") parent-bol ,offset)
       ((parent-is "field_definition") parent-bol 0)
       ((parent-is "arguments_definition") parent-bol ,offset)
       ((parent-is "input_value_definition") parent-bol 0)
       ((parent-is "enum_values_definition") parent-bol ,offset)
       ((parent-is "enum_value_definition") parent-bol 0)
       ((parent-is "input_fields_definition") parent-bol ,offset)
       ((parent-is "root_operation_type_definition") parent-bol ,offset)
       ((parent-is "variable_definitions") parent-bol ,offset)
       ((parent-is "selection_set") parent-bol ,offset)
       ((parent-is "arguments") parent-bol ,offset)
       ((parent-is "argument") parent-bol 0)
       ((parent-is "object_value") parent-bol ,offset)
       ((parent-is "list_value") parent-bol ,offset)
       ((parent-is "string_value") parent-bol 0)
       ((parent-is "definition") parent-bol 0))))
  "Tree sitter indentation rules for `graphql-ts-mode'.")

(defvar graphql-ts-mode--font-lock-settings
  (treesit-font-lock-rules
   :language 'graphql
   :feature 'comment
   '((comment) @font-lock-comment-face)

   :language 'graphql
   :feature 'bracket
   '((["(" ")" "{" "}" "[" "]"]) @font-lock-bracket-face)

   :language 'graphql
   :feature 'delimiter
   '((":") @font-lock-delimiter-face)

   :language 'graphql
   :feature 'constant
   '([([(boolean_value) (null_value)] @font-lock-constant-face)
      ((directive_location) @font-lock-constant-face)])

   :language 'graphql
   :feature 'string
   '([((string_value) @font-lock-string-face)
      ((description) @font-lock-doc-face)])

   :language 'graphql
   :feature 'number
   '([(int_value) (float_value)] @font-lock-number-face)

   :language 'graphql
   :feature 'variable
   '([((variable) @font-lock-variable-use-face)
      (input_value_definition (name) @font-lock-variable-name-face)
      (argument (name) @font-lock-variable-name-face)
      (object_field (name) @font-lock-property-name-face)])

   :language 'graphql
   :feature 'type
   '([((type) @font-lock-type-face)
      ((named_type) @font-lock-type-face)])

   :language 'graphql
   :feature 'keyword
   `([,@graphql-ts-mode--keywords] @font-lock-keyword-face)

   :language 'graphql
   :feature 'keyword
   '((directive "@" @font-lock-builtin-face (name) @font-lock-builtin-face))

   :language 'graphql
   :feature 'definition
   '([(object_type_definition (name) @font-lock-function-name-face)
      (enum_type_definition (name) @font-lock-function-name-face)
      (input_object_type_definition (name) @font-lock-function-name-face)
      (union_type_definition (name) @font-lock-function-name-face)
      (interface_type_definition (name) @font-lock-function-name-face)
      (scalar_type_definition (name) @font-lock-function-name-face)
      (fragment_definition (fragment_name) @font-lock-function-name-face)
      (directive_definition ("@" @font-lock-function-name-face
                             (name) @font-lock-function-name-face))]))
  "Tree sitter font lock rules for `graphql-ts-mode'.")

(defvar graphql-ts-mode--imenu-settings
  '(("Schema" "schema_definition")
    ("Fragment" "fragment_definition")
    ("Scalar" "scalar_type_definition")
    ("Object" "^object_type_definition")
    ("Interface" "interface_type_definition")
    ("Union" "union_type_definition")
    ("Enum" "enum_type_definition")
    ("Input" "input_object_type_definition")
    ("Directive" "directive_definition")
    ("Operation" "operation_definition"))
  "Tree sitter imenu settings for `graphql-ts-mode'.")

(defun graphql-ts-mode--fill-paragraph (&optional justify)
  "Fill and possibly JUSTIFY paragraph, making sure to stay inside strings."
  (or
   ;; Standard comment handling works fine
   (fill-comment-paragraph justify)
   ;; Inside a string we want to make sure we stay inside the string
   (when-let* ((node (treesit-thing-at-point "string_value" nil))
               (start (treesit-node-start node))
               (end (treesit-node-end node)))
     (save-excursion
       (move-to-left-margin)
       (let ((end (progn (forward-paragraph 1) (min (point) end)))
             (beg (progn (forward-paragraph -1) (max (point) start))))
         (fill-region beg end justify)))
     t)
   ;; We're not in a comment and not in a string, so nothing should happen.
   t))

(defun graphql-ts-mode--defun-name (node)
  "Return the GraphQL defun name for NODE, or NIL."
  (cl-flet ((capture (q)
              (mapconcat #'treesit-node-text
                         (treesit-query-capture node q nil nil t))))
    (pcase (treesit-node-type node)
      ("scalar_type_definition"
       (capture '((scalar_type_definition (name) @name))))
      ("object_type_definition"
       (capture '((object_type_definition (name) @name))))
      ("union_type_definition"
       (capture '((union_type_definition (name) @name))))
      ("enum_type_definition"
       (capture '((enum_type_definition (name) @name))))
      ("input_object_type_definition"
       (capture '((input_object_type_definition (name) @name))))
      ("interface_type_definition"
       (capture '((interface_type_definition (name) @name))))
      ("directive_definition"
       (capture '((directive_definition "@" @a (name) @name)))))))

(defun graphql-ts-mode--pair-block-string ()
  "Complete quotes for a block string when using `electric-pair-mode'."
  (when (and electric-pair-mode
             (eq ?\" last-command-event)
             (eq 3 (cl-loop for n from 0
                            while (eq ?\" (char-before (- (point) n)))
                            count 1)))
    (save-excursion (insert "\"\""))))

;;;###autoload
(define-derived-mode graphql-ts-mode prog-mode "GraphQL"
  "Major mode for editing GraphQL, powered by tree-sitter."
  :syntax-table graphql-ts-mode--syntax-table

  (setq-local comment-start "# ")
  (setq-local comment-start-skip "#+[ \t]*")
  (setq-local comment-end "")

  (when (treesit-ready-p 'graphql)
    (treesit-parser-create 'graphql)

    (setq-local treesit-simple-indent-rules graphql-ts-mode--indent-rules)

    (setq-local treesit-font-lock-settings graphql-ts-mode--font-lock-settings)
    (setq-local treesit-font-lock-feature-list
                '((comment constant definition)
                  (keyword string number type variable)
                  (bracket delimiter)))

    (setq-local treesit-defun-type-regexp
                (rx (seq (or "schema"
                             "type"
                             "directive"
                             "operation"
                             "fragment")
                         "_definition")))
    (setq-local treesit-simple-imenu-settings graphql-ts-mode--imenu-settings)
    (setq-local treesit-defun-name-function #'graphql-ts-mode--defun-name)

    (setq-local electric-indent-chars
                (append "(){}[]" electric-indent-chars))

    (add-hook 'post-self-insert-hook
              #'graphql-ts-mode--pair-block-string 90 t)

    (setq-local fill-paragraph-function #'graphql-ts-mode--fill-paragraph)
    ;; paragraph-{start,separate} are set so that block strings where the
    ;; quotes are on separate lines stay that way.
    (setq-local paragraph-start "\f\\|[ \t]*$\\|[ \t]*\"\"\"[ \t]*$")
    (setq-local paragraph-separate "[ \t\f]*$\\|[ \t]*\"\"\"[ \t]*$")

    (treesit-major-mode-setup)))

;;;###autoload
(add-to-list 'auto-mode-alist '("\\.graphql\\'"  . graphql-ts-mode))
;;;###autoload
(add-to-list 'auto-mode-alist '("\\.graphqls\\'"  . graphql-ts-mode))
;;;###autoload
(add-to-list 'auto-mode-alist '("\\.gql\\'"  . graphql-ts-mode))

(provide 'graphql-ts-mode)

;;; graphql-ts-mode.el ends here
