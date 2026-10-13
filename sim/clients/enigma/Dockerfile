# hs-sim client image: official Tailscale container + test tools + the simulated university root CA.
ARG TS_VERSION
FROM tailscale/tailscale:v${TS_VERSION}
RUN apk add --no-cache socat iperf3 netcat-openbsd iproute2-tc bind-tools ca-certificates
COPY root_ca.crt /usr/local/share/ca-certificates/hs-sim-root.crt
RUN update-ca-certificates 2>/dev/null
