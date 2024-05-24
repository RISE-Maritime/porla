FROM python:3.11-slim-bullseye

ADD https://github.com/krallin/tini/releases/download/v0.19.0/tini /tini
RUN chmod +x /tini

RUN apt-get update && apt-get install -y \
    socat \
    jq \
    parallel \
    && rm -rf /var/lib/apt/lists/*

COPY requirements.txt requirements.txt
RUN pip3 install --no-cache-dir -r requirements.txt

COPY --chmod=555 ./bin/* /usr/local/bin/
COPY bash-init.sh /bash-init.sh

ENV BASH_ENV=/bash-init.sh

ENTRYPOINT ["/tini", "-g", "--", "/bin/bash", "-c"]