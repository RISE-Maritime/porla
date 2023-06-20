FROM python:3.11-slim-bullseye

RUN apt-get update && apt-get install -y \
    netcat-openbsd \
    socat \
    mosquitto-clients \
    jq \
    jo \
    && rm -rf /var/lib/apt/lists/*

COPY requirements.txt requirements.txt
RUN pip3 install --no-cache-dir -r requirements.txt

COPY --chmod=555 ./bin/* /usr/local/bin/
COPY bash-init.sh /bash-init.sh

ENV BASH_ENV=/bash-init.sh

ENTRYPOINT ["/bin/bash", "-l", "-c"]