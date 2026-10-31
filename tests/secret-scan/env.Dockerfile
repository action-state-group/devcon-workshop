# The scanner's second negative test: a secret in the image config next to a harmless entry.
FROM busybox:1.36
ENV DO_NOT_TRACK=1 API_KEY=not-a-real-key
