;;; extensions.lisp
;; extensions and helper functions for
;;  tooter objects

(in-package #:glacier)

(defvar *no-bot-regex* "(?i)#?NoBot"
  "regex to check for the NoBot tag")

(defun api-request (fragment &optional result-type)
  "perform an API request

FRAGMENT is the fragment of the url that goes AFTER api/v1/
RESULT-TYPE (if provided) is the object type that we should use when parsing the response
can be either a symbol ('account) or list '(:list account)

if it is a list then we decode the response and collect and return them as a list"
  (let ((client (bot-client *bot*)))
    (multiple-value-bind (response headers)
	(tooter:request (concatenate 'string
				     (tooter:base client)
				     "/api/v1/"
				     fragment)
			:headers `(("Authorization" . ,(concatenate 'string
								    "Bearer "
								    (tooter:access-token client)))))
      (values
       (if result-type
	   (if (listp result-type)
	       (loop for r in response
		     collect (tooter:decode-entity
			      (find-symbol (symbol-name (car (last result-type)))
					   (find-package :tooter))
			      r))
	       (tooter:decode-entity result-type response))
	   response)
       headers))))

(defmethod no-bot-p ((id string))
  "checks an account's bio and profile fields to see if they contain a NoBot tag"
  (no-bot-p (tooter:find-account (bot-client *bot*) id)))

(defmethod no-bot-p ((account tooter:account))
  "checks an account's bio and profile fields to see if they contain a NoBot tag"
  (or (cl-ppcre:scan *no-bot-regex* (tooter:note account))
      (loop for field in (tooter:fields account)
            for name = (tooter:name field)
            for value = (tooter::value field)
	    when (or (cl-ppcre:scan *no-bot-regex* name)
                     (cl-ppcre:scan *no-bot-regex* value))
            collect field)))

(defmethod no-bot-p ((mention tooter:mention))
  "checks account found in MENTION to see if they have NoBot set"
  (no-bot-p (tooter:find-account (bot-client *bot*) (tooter:id mention))))

(defmethod reply ((status tooter:status) text &key include-mentions media cw sensitive visibility idempotency-key)
  "replies to a STATUS with TEXT. copies the visibility and content warning as the post it's replying to

if INCLUDE-MENTIONS is non-nil, include mentions besides the primary account being replied to"
  (let* ((client (bot-client *bot*))
	 (reply-account (tooter:account status))
	 (reply-mentions (loop for mention in (remove (tooter:id reply-account)
						      (tooter:mentions status)
						      :test #'equal :key #'tooter:id)
			    unless (no-bot-p mention)
					
			    collect (concatenate 'string "@" (tooter::account-name mention)))))
    (tooter:make-status client (str:join " "
					 `(,(concatenate 'string "@" (tooter::account-name reply-account))
					   ,@(when include-mentions reply-mentions)
					   ,text))
			:media media
			:sensitive sensitive
			:visibility (or visibility (tooter:visibility status))
			:spoiler-text (or cw (tooter:spoiler-text status))
			:in-reply-to (tooter:id status)
			:idempotency-key idempotency-key)))

(defun post (text &key (visibility :unlisted) cw sensitive media idempotency-key)
  "a thin wrapper around tooter:make-status

see documentation for that function"
  (tooter:make-status (bot-client *bot*)
		      text
		      :visibility visibility
		      :spoiler-text cw
		      :media media
		      :sensitive sensitive
		      :idempotency-key idempotency-key))

;; strips out html-tags/bot-username if we have that set in our config
(defmethod tooter:decode-entity :after ((status tooter:status) data)
  (when (config :strip-html t)
    (setf (tooter:content status) (tooter:plain-format-html (tooter:content status))))
  (when (config :strip-bot-username)
    (setf (tooter:content status) (str:replace-all (bot-username *bot*) "" (tooter:content status))))
  status)
