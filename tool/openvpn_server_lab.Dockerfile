# Local isolated interoperability lab; not an Android build or distributed image.
FROM blackout-openvpn3-host:review
RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends openvpn iproute2 python3 cmake make && rm -rf /var/lib/apt/lists/*
WORKDIR /work
