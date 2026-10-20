;;; ths-theme.el --- Shared dashboard and chart palettes -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later

;;; Code:
(require 'ths-data)

(defvar ths-theme-change-hook nil
  "Hook run after changing the THS color theme.")

(defcustom ths-theme 'dark
  "Color theme used by THS, independently of the Emacs frame theme."
  :type '(choice (const :tag "Dark" dark) (const :tag "Light" light))
  :group 'ths
  :set (lambda (symbol value)
         (unless (memq value '(dark light)) (error "Unknown THS theme: %s" value))
         (set-default symbol value)
         (run-hooks 'ths-theme-change-hook)))

(defconst ths-theme--colors
  '((background "#0b1423" "#eef2f7")
    (foreground "#dce5f4" "#1f2937")
    (panel "#111c2e" "#ffffff")
    (alternate "#17243a" "#f3f6fa")
    (selected "#263d60" "#dbeafe")
    (selected-text "#ffffff" "#123c70")
    (button "#192438" "#e4eaf2")
    (button-text "#a7b8cf" "#334155")
    (hover "#304767" "#cbdcf2")
    (row-hover "#22334e" "#e8f0fb")
    (secondary "#91a4c1" "#526176")
    (muted "#63738d" "#66758a")
    (neutral "#c8d2e3" "#334155")
    (border "#30415b" "#cbd5e1")
    (grid "#26344a" "#e0e6ee")
    (baseline "#64758e" "#94a3b8")
    (axis "#8496b0" "#596b82")
    (up "#ff646e" "#c62828")
    (down "#39d6a0" "#087f5b")
    (warning "#f4c96b" "#946200")
    (line "#73b7ff" "#1565c0")
    (area "#55aaff" "#3b82f6")
    (point "#a6d5ff" "#0d47a1"))
  "Semantic colors, each specified as (ROLE DARK LIGHT).")

(defun ths-theme-color (role)
  "Return the current theme's color for ROLE."
  (or (nth (if (eq ths-theme 'light) 2 1) (assq role ths-theme--colors))
      (error "Unknown THS color role: %s" role)))

(provide 'ths-theme)
;;; ths-theme.el ends here
