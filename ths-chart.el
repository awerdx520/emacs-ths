;;; ths-chart.el --- SVG and terminal charts for THS -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later

;;; Commentary:
;; Graphical frames use a continuous SVG plot through ETAF's image Host.
;; Terminal frames use text charts with faces.

;;; Code:
(require 'cl-lib)
(require 'xml)
(require 'ths-data)

(defconst ths-chart-up "#ff646e")
(defconst ths-chart-down "#39d6a0")
(defconst ths-chart-muted "#63738d")

(defun ths-chart--volume-label (volume)
  "Format VOLUME in lots with compact Chinese magnitude labels."
  (cond ((null volume) "--")
        ((>= volume 100000000) (format "%.1f亿" (/ volume 100000000.0)))
        ((>= volume 10000) (format "%.1f万" (/ volume 10000.0)))
        (t (format "%.0f" volume))))

(defun ths-chart--volume-bars (rows positions &optional daily base)
  "Pair ROWS with POSITIONS and price colors, using DAILY candles or BASE.
Volumes remain in lots; an absent value is distinct from zero."
  (cl-loop for row in rows for x in positions
           for price = (plist-get row (if daily :close :price))
           for reference = (if daily (plist-get row :open) (or base price))
           collect (list :x x :volume (ths-data--volume (plist-get row :volume))
                         :time (plist-get row (if daily :date :time))
                         :color (if (>= price reference) ths-chart-up ths-chart-down))
           do (setq base price)))

(defun ths-chart--volume-svg (bars width left right)
  "Draw BARS of WIDTH between LEFT and RIGHT below the price panel."
  (let* ((values (delq nil (mapcar (lambda (bar) (plist-get bar :volume)) bars)))
         (maximum (if values (apply #'max values) 0))
         (scale (max 1.0 (float maximum))))
    (concat
     "<g id=\"volume-panel\">"
     (format "<path d=\"M%.2f 246 H%.2f M%.2f 294 H%.2f\" stroke=\"#26344a\"/>" left right left right)
     (format "<text x=\"%.2f\" y=\"232\" fill=\"#91a4c1\">成交量（手） · 最新 %s%s</text>"
             left (ths-chart--volume-label (plist-get (car (last bars)) :volume))
             (if values "" " · 暂无数据"))
     (format "<text x=\"%.2f\" y=\"250\" text-anchor=\"end\" fill=\"#63738d\">%s</text>"
             (- left 10) (if values (ths-chart--volume-label maximum) "--"))
     (format "<text x=\"%.2f\" y=\"298\" text-anchor=\"end\" fill=\"#63738d\">0</text>" (- left 10))
     (mapconcat
      (lambda (bar)
        (if-let* ((volume (plist-get bar :volume)))
            (let* ((x (plist-get bar :x)) (height (* 48.0 (/ volume scale)))
                   (start (max left (- x (/ width 2))))
                   (end (min right (+ x (/ width 2)))))
              (format (concat "<rect class=\"volume-bar\" data-time=\"%s\" data-volume=\"%s\" "
                              "x=\"%.2f\" y=\"%.2f\" width=\"%.2f\" height=\"%.2f\" fill=\"%s\"/>")
                      (xml-escape-string (or (plist-get bar :time) "")) volume
                      start (- 294 height) (- end start) height (plist-get bar :color)))
          "")) bars "")
     "</g>")))

(defun ths-chart-svg (stock)
  "Return a continuous intraday SVG chart for STOCK.
Prices and their running arithmetic mean share a symmetric percentage axis.
The SVG is self-contained; no external files, scripts or fonts are fetched."
  (when (and (plist-get stock :points) (ths-data-chart-base stock))
    (let* ((points (plist-get stock :points))
           (prices (ths-data-series stock))
           (base (ths-data-chart-base stock))
           (radius (max (* base 0.007)
                        (* 1.15 (apply #'max (mapcar (lambda (p) (abs (- p base))) prices)))))
           (low (- base radius)) (high (+ base radius))
           (left 68.0) (right 644.0) (top 26.0) (bottom 210.0)
           (total 0.0) (means nil))
      (cl-loop for price in prices for i from 1
               do (cl-incf total price) do (push (/ total i) means))
      (cl-labels
       ((x (point) (+ left (* (/ (plist-get point :slot) 240.0) (- right left))))
        (y (price) (+ top (* (/ (- high price) (- high low)) (- bottom top))))
        (path (values)
          (mapconcat #'identity
                     (cl-loop for price in values for point in points for i from 0
                              collect (format "%s%.2f,%.2f" (if (= i 0) "M" "L") (x point) (y price))) " ")))
       (let ((line (path prices)))
         (concat
          "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"720\" height=\"340\" viewBox=\"0 0 720 340\" preserveAspectRatio=\"none\">"
          "<defs><linearGradient id=\"area\" x1=\"0\" y1=\"0\" x2=\"0\" y2=\"1\">"
          "<stop offset=\"0%\" stop-color=\"#55aaff\" stop-opacity=\"0.24\"/>"
          "<stop offset=\"100%\" stop-color=\"#55aaff\" stop-opacity=\"0.015\"/>"
          "</linearGradient></defs><rect width=\"720\" height=\"340\" fill=\"#111c2e\"/>"
          "<g font-family=\"monospace\" font-size=\"12\">"
          (mapconcat
           #'identity
           (cl-loop for i from 0 to 4
                    for price = (- high (* (/ i 4.0) (- high low)))
                    for py = (y price)
                    for color = (cond ((< i 2) ths-chart-up) ((> i 2) ths-chart-down) (t "#91a4c1"))
                    collect
                    (format (concat "<path d=\"M68 %.2f H644\" stroke=\"%s\" stroke-width=\"1\" stroke-dasharray=\"%s\"/>"
                                    "<text x=\"58\" y=\"%.2f\" text-anchor=\"end\" fill=\"%s\">%.2f</text>"
                                    "<text x=\"656\" y=\"%.2f\" fill=\"%s\">%+.2f%%</text>")
                            py (if (= i 2) "#64758e" "#26344a") (if (= i 2) "5 4" "2 4")
                            (+ py 4) color price (+ py 4) color (* 100 (/ (- price base) base)))) "")
          (mapconcat
           #'identity
           (cl-loop for i from 0 to 4 for px = (+ left (* (/ i 4.0) (- right left)))
                    collect (format "<path d=\"M%.2f 26 V294\" stroke=\"#26344a\" stroke-dasharray=\"2 4\"/>" px)) "")
          (format "<path d=\"%s L%.2f 210 L%.2f 210 Z\" fill=\"url(#area)\"/>"
                  line (x (car (last points))) (x (car points)))
          (format "<path id=\"mean-line\" d=\"%s\" fill=\"none\" stroke=\"#f4c96b\" stroke-width=\"1.6\" stroke-linejoin=\"round\"/>" (path (nreverse means)))
          (format "<path id=\"price-line\" d=\"%s\" fill=\"none\" stroke=\"#73b7ff\" stroke-width=\"2.1\" stroke-linejoin=\"round\" stroke-linecap=\"round\"/>" line)
          (format "<circle cx=\"%.2f\" cy=\"%.2f\" r=\"3.2\" fill=\"#a6d5ff\"/>"
                  (x (car (last points))) (y (car (last prices))))
          (ths-chart--volume-svg
           (ths-chart--volume-bars points (mapcar #'x points) nil base) 1.8 left right)
          "<g fill=\"#8496b0\" font-size=\"12\"><text x=\"68\" y=\"322\">09:30</text>"
          "<text x=\"212\" y=\"322\" text-anchor=\"middle\">10:30</text>"
          "<text x=\"356\" y=\"322\" text-anchor=\"middle\">11:30 / 13:00</text>"
          "<text x=\"500\" y=\"322\" text-anchor=\"middle\">14:00</text>"
          "<text x=\"644\" y=\"322\" text-anchor=\"end\">15:00</text></g></g></svg>"))))))

(defun ths-chart-candles-svg (stock &optional count)
  "Draw STOCK's latest COUNT daily candles in a self-contained SVG.
Wicks, bodies and axes share pixel coordinates, independent of Emacs fonts.
Return nil when no candles are available."
  (when-let* ((candles (ths-data-candles stock (max 1 (or count 48)))))
    (let* ((minimum (apply #'min (mapcar (lambda (c) (plist-get c :low)) candles)))
           (maximum (apply #'max (mapcar (lambda (c) (plist-get c :high)) candles)))
           (padding (max 0.01 (* maximum 0.005) (* (- maximum minimum) 0.08)))
           (low (- minimum padding)) (high (+ maximum padding))
           (left 76.0) (right 700.0) (top 26.0) (bottom 210.0)
           (n (length candles)) (step (/ (- right left) n))
           (body-width (min 14.0 (* step 0.6))))
      (cl-labels
          ((x (i) (+ left (* (+ i 0.5) step)))
           (y (price) (+ top (* (/ (- high price) (- high low)) (- bottom top)))))
        (concat
         "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"720\" height=\"340\" viewBox=\"0 0 720 340\" preserveAspectRatio=\"none\">"
         "<rect width=\"720\" height=\"340\" fill=\"#111c2e\"/>"
         "<g font-family=\"monospace\" font-size=\"12\">"
         (mapconcat
          #'identity
          (cl-loop for i from 0 to 4
                   for price = (- high (* (/ i 4.0) (- high low)))
                   for py = (y price)
                   collect
                   (format (concat "<path d=\"M76 %.2f H700\" stroke=\"#26344a\" stroke-dasharray=\"2 4\"/>"
                                   "<text x=\"66\" y=\"%.2f\" text-anchor=\"end\" fill=\"#91a4c1\">%.2f</text>")
                           py (+ py 4) price)) "")
         (mapconcat
          #'identity
          (cl-loop for candle in candles for i from 0
                   for px = (x i)
                   for open = (plist-get candle :open)
                   for close = (plist-get candle :close)
                   for color = (if (>= close open) ths-chart-up ths-chart-down)
                   for body-top = (y (max open close))
                   for body-bottom = (y (min open close))
                   collect
                   (concat
                    (format "<g class=\"candle\" data-date=\"%s\">"
                            (xml-escape-string (or (plist-get candle :date) "")))
                    (format "<line class=\"wick\" x1=\"%.2f\" y1=\"%.2f\" x2=\"%.2f\" y2=\"%.2f\" stroke=\"%s\" stroke-width=\"1\"/>"
                            px (y (plist-get candle :high)) px (y (plist-get candle :low)) color)
                    (if (= open close)
                        (format "<line class=\"body\" x1=\"%.2f\" y1=\"%.2f\" x2=\"%.2f\" y2=\"%.2f\" stroke=\"%s\" stroke-width=\"1\"/>"
                                (- px (/ body-width 2)) body-top (+ px (/ body-width 2)) body-top color)
                      (format "<rect class=\"body\" x=\"%.2f\" y=\"%.2f\" width=\"%.2f\" height=\"%.2f\" fill=\"%s\"/>"
                              (- px (/ body-width 2)) body-top body-width
                              (max 1.0 (- body-bottom body-top)) color))
                    "</g>")) "")
         (ths-chart--volume-svg
          (ths-chart--volume-bars candles (mapcar #'x (number-sequence 0 (1- n))) t)
          body-width left right)
         (mapconcat
          (lambda (i)
            (format "<text class=\"date-label\" x=\"%.2f\" y=\"322\" text-anchor=\"%s\" fill=\"#8496b0\">%s</text>"
                    (cond ((= n 1) (x i)) ((= i 0) left) ((= i (1- n)) right) (t (x i)))
                    (cond ((= n 1) "middle") ((= i 0) "start") ((= i (1- n)) "end") (t "middle"))
                    (xml-escape-string (or (plist-get (nth i candles) :date) "--"))))
          (delete-dups (list 0 (/ (1- n) 2) (1- n))) "")
         "</g></svg>")))))

(defun ths-chart--row (value low high height)
  "Map VALUE within LOW and HIGH to a row in HEIGHT."
  (max 0 (min (1- height)
              (round (* (1- height) (/ (- high value) (max 0.001 (- high low))))))))

(defun ths-chart--render (grid low high)
  "Add axis labels to GRID spanning LOW to HIGH."
  (let ((height (length grid)))
    (mapconcat
     (lambda (i)
       (concat (propertize
                (format "%8.2f │" (- high (* (/ (float i) (1- height)) (- high low))))
                'face `(:foreground ,ths-chart-muted))
               (mapconcat #'identity (aref grid i) "")))
     (number-sequence 0 (1- height)) "\n")))

(defun ths-chart--volume-text (bars width height heading)
  "Render BARS in WIDTH columns and HEIGHT rows, optionally with HEADING.
Sum volumes that fall in the same terminal column, retaining its last color."
  (let ((values (make-vector width nil)) (colors (make-vector width nil)))
    (dolist (bar bars)
      (when-let* ((volume (plist-get bar :volume)))
        (let ((x (plist-get bar :x)))
          (aset values x (+ (or (aref values x) 0) volume))
          (aset colors x (plist-get bar :color)))))
    (let* ((known (delq nil (append values nil)))
           (maximum (if known (apply #'max known) 0))
           (scale (max 1.0 (float maximum))))
      (concat
       (when heading
         (concat (propertize
                  (truncate-string-to-width
                   (concat "成交量（手） · 柱峰 " (if known (ths-chart--volume-label maximum) "--"))
                   (+ width 10) 0 ?\s)
                  'face `(:foreground ,ths-chart-muted)) "\n"))
       (mapconcat
        (lambda (i)
          (concat
           (propertize
            (concat (truncate-string-to-width
                     (cond ((not heading) "量/手")
                           ((= i 0) (ths-chart--volume-label maximum))
                           ((= i (1- height)) "0") (t "")) 8 0 ?\s) " │")
            'face `(:foreground ,ths-chart-muted))
           (if (and (not known) (= i 0))
               (truncate-string-to-width "暂无成交量" width 0 ?\s)
             (mapconcat
              (lambda (x)
                (let* ((volume (or (aref values x) 0))
                       (level (max 0 (min 8 (ceiling (- (* height 8 (/ volume scale))
                                                       (* 8 (- height i 1))))))))
                  (propertize (substring " ▁▂▃▄▅▆▇█" level (1+ level))
                              'face `(:foreground ,(or (aref colors x) ths-chart-muted)))))
              (number-sequence 0 (1- width)) ""))))
        (number-sequence 0 (1- height)) "\n")))))

(defun ths-chart-line (stock &optional width height)
  "Draw STOCK's intraday prices and volume within WIDTH and HEIGHT."
  (if (null (plist-get stock :points)) "暂无分时数据"
    (let* ((width (max 8 (or width 48))) (rows (max 3 (or height 12)))
           (volume-rows (max 1 (/ rows 4))) (heading (>= rows 5))
           (height (- rows volume-rows (if heading 1 0)))
           (points (plist-get stock :points))
           (positions (mapcar (lambda (point)
                                (min (1- width) (round (* (/ (plist-get point :slot) 240.0) (1- width))))) points))
           (prices (ths-data-series stock))
           (low (* 0.999 (apply #'min prices)))
           (high (* 1.001 (apply #'max prices)))
           (grid (vconcat (cl-loop repeat height collect (make-vector width " "))))
           (previous nil) (total 0.0))
      (cl-loop for value in prices for point in (plist-get stock :points) for i from 1
               for x = (min (1- width) (round (* (/ (plist-get point :slot) 240.0) (1- width))))
               for y = (ths-chart--row value low high height)
               do (cl-incf total value)
               do (when previous
                    (cl-loop for row from (min previous y) to (max previous y)
                             do (aset (aref grid row) x
                                      (propertize "│" 'face '(:foreground "#73b7ff")))))
               do (aset (aref grid (ths-chart--row (/ total i) low high height)) x
                        (propertize "·" 'face '(:foreground "#f4c96b")))
               do (aset (aref grid y) x (propertize "●" 'face '(:foreground "#73b7ff")))
               do (setq previous y))
      (concat (ths-chart--render grid low high) "\n"
              (ths-chart--volume-text
               (ths-chart--volume-bars points positions nil (ths-data-chart-base stock))
               width volume-rows heading)))))

(defun ths-chart-candles (stock &optional count height)
  "Draw COUNT unadjusted candles and their volume within HEIGHT rows."
  (if (null (plist-get stock :candles)) "暂无日 K 数据"
    (let* ((candles (ths-data-candles stock (or count 24)))
           (rows (max 3 (or height 12)))
           (volume-rows (max 1 (/ rows 4))) (heading (>= rows 5))
           (height (- rows volume-rows (if heading 1 0)))
           (low (apply #'min (mapcar (lambda (c) (plist-get c :low)) candles)))
           (high (apply #'max (mapcar (lambda (c) (plist-get c :high)) candles)))
           (grid (vconcat (cl-loop repeat height collect (make-vector (* 2 (length candles)) " ")))))
      (cl-loop for candle in candles for x from 0 by 2
               for open = (plist-get candle :open) for close = (plist-get candle :close)
               for color = (if (>= close open) ths-chart-up ths-chart-down)
               do (cl-loop for row from (ths-chart--row (plist-get candle :high) low high height)
                           to (ths-chart--row (plist-get candle :low) low high height)
                           do (aset (aref grid row) x (propertize "│" 'face `(:foreground ,color))))
               do (cl-loop for row from (ths-chart--row (max open close) low high height)
                           to (ths-chart--row (min open close) low high height)
                           do (aset (aref grid row) x (propertize "┃" 'face `(:foreground ,color)))))
      (concat (ths-chart--render grid low high) "\n"
              (ths-chart--volume-text
               (ths-chart--volume-bars candles (number-sequence 0 (* 2 (1- (length candles))) 2) t)
               (* 2 (length candles)) volume-rows heading)))))

(provide 'ths-chart)
;;; ths-chart.el ends here
