# A simulated lab PC: Tailscale (userspace) + OpenSSH + the real setup-lab-pc.sh (labsched, slot-switch).
FROM tailscale/tailscale:v1.102.3 AS ts

FROM debian:13-slim
RUN apt-get update && apt-get install -y --no-install-recommends openssh-server sudo procps passwd ca-certificates \
 && rm -rf /var/lib/apt/lists/* && mkdir -p /run/sshd /var/lib/tailscale
COPY --from=ts /usr/local/bin/tailscale /usr/local/bin/tailscaled /usr/local/bin/
COPY setup-lab-pc.sh /setup-lab-pc.sh
COPY entry.sh /entry.sh
RUN chmod +x /entry.sh && useradd -m labadmin && bash /setup-lab-pc.sh labadmin
CMD ["/entry.sh"]
