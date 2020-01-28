(in-package #:glacier)

(defun parse-time (amount duration)
  "parses AMOUNT of DURATION into seconds"
  (* amount (cond
	     ((or (eq duration :seconds)
		  (eq duration :second))
	      1)
	     ((or (eq duration :minutes)
		  (eq duration :minute))
	      60)
	     ((or (eq duration :hours)
		  (eq duration :hour))
	      3600)
	     ((or (eq duration :days)
		  (eq duration :day))
	      86400)
	     ((or (eq duration :weeks)
		  (eq duration :week))
	      604800)
	     (t (error "unknown duration")))))

(defmacro after ((amount duration &key async) &body body)
  "runs BODY after AMOUNT of DURATION

if ASYNC is non-nil, runs asynchronously"
  (let ((code `((sleep (parse-time ,amount ,duration))
		,@body)))
    (if async
	`(bt:make-thread
	  (lambda () ,@code))
	`(progn ,@code))))

(defmacro after-every ((amount duration &key async run-immediately) &body body)
  "runs BODY after every AMOUNT of DURATION

if ASYNC is non-nil, runs asynchronously
if RUN-IMMEDIATELY is non-nil, runs BODY once before waiting for next invocation"
  (let ((code `(loop ,@(when run-immediately `(initially ,@body))
		     do (sleep (parse-time ,amount ,duration))
		     ,@body)))
    (if async
	`(bt:make-thread
	  (lambda () ,code))
	code)))

(defun agetf (place indicator &optional default)
  "getf but for alists"
  (or (cdr (assoc indicator place :test #'equal))
      default))

(defun get-mastodon-streaming-url ()
  "gets the websocket url for the mastodon instance"
  (gethash "streaming_api" (tooter:urls (tooter:instance (bot-client *bot*)))))

(defun print-open ()
  "prints a message when the websocket is connected"
  (print "websocket connected"))

(defun print-close (&key code reason)
  "prints a message when the websocket is closed"
  (when (and code reason)
    (format t "websocket closed because ~A (code=~A)~%" reason code)))

(defun add-scheme (domain)
  "adds https scheme to DOMAIN if it isnt already there"
  (if (search "https://" domain)
      domain
      (concatenate 'string
		   "https://"
		   domain)))

(defun commandp (word)
  "checks if WORD is a command"
  (str:starts-with-p "!" word))

(defun add-command (cmd function &key privileged)
  "adds a command into our hash

CMD should be a string
FUNCTION should be a function that accepts a single parameter (a tooter:status object)"
  (setf (gethash cmd (if privileged
			 *privileged-commands*
			 *commands*)) function))

(defun privileged-reply-p (status)
  "returns T if STATUS is from an account that the bot follows"
  (tooter:following (car
		     (tooter:relationships
		      (bot-client *bot*)
		      (list (tooter:id (tooter:account status)))))))

(defun fave-p (notification)
  (eq (tooter:kind notification) :favourite))

(defun mention-p (notification)
  (eq (tooter:kind notification) :mention))

(defun boost-p (notification)
  (eq (tooter:kind notification) :reblog))

(defun poll-ended-p (notification)
  (eq (tooter:kind notification) :poll))

(defun follow-request-p (notification)
  (eq (tooter:kind notification) :follow-request))

(defun follow-p (notification)
  (eq (tooter:kind notification) :follow))

(defun bot-post-p (status)
  "checks if STATUS was posted by the bot"
  (equal (bot-account-id *bot*) (tooter:id (tooter:account status))))

(defun delete-parent (status)
  "deletes the parent post of STATUS if it was posted by the bot"
  (let ((parent (tooter:find-status (bot-client *bot*) (tooter:in-reply-to-id status))))
    (when (bot-post-p parent)
      (tooter:delete-status (bot-client *bot*) parent))))
