# The scanner's negative test: a secret copied in one layer and deleted in the next must be found.
FROM busybox:1.36
RUN mkdir -p /home/p/.devcon8 && echo "not-a-real-invite" > /home/p/.devcon8/join.txt
RUN rm /home/p/.devcon8/join.txt
