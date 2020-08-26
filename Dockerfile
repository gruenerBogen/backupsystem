FROM debian:buster-slim

RUN apt-get update && \
    apt-get -y install live-build make

WORKDIR /data

CMD /bin/bash
