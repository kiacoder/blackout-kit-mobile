# Local host evaluation only; not a distribution or Android build.
FROM ubuntu:24.04
RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    g++ ca-certificates libasio-dev libssl-dev liblz4-dev libxxhash-dev pkg-config \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /work
