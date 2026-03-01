FROM ubuntu:22.04

RUN apt-get update && apt-get install -y \
    curl \
    git \
    jq \
    docker.io \
    && rm -rf /var/lib/apt/lists/*

COPY golem.sh /usr/local/bin/golem.sh
RUN chmod +x /usr/local/bin/golem.sh

# Git identity for golem
RUN git config --global user.email "golem@cyberstorm.dev" && \
    git config --global user.name "Golem Executor"

ENTRYPOINT ["bash", "/usr/local/bin/golem.sh"]
