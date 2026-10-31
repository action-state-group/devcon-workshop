# The scanner's third negative test: a PEM private key (text) must be found, while binaries that
# merely name the PEM header (libssh) are not.
FROM busybox:1.36
RUN printf -- '-----BEGIN OPENSSH PRIVATE KEY-----\nnot-a-real-key\n-----END OPENSSH PRIVATE KEY-----\n' > /id_test
