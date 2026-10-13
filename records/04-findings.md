# 04 — Findings for the real pilot

1. **Relayed connections don't survive a Headscale outage.** The campus DERP relay is built into
   Headscale, so stopping Headscale also stops the relay. In a 30-minute outage, a direct connection lost
   0 % of its traffic; a relayed one lost 92 %. The proposal's claim that "existing sessions keep working"
   holds only for direct connections.
   *Recommendation:* run the relay as its own `derper` service, ideally on a second machine, so that a
   Headscale restart or upgrade doesn't cut relayed users off.

2. **Relayed traffic can leave the country.** With Tailscale's public relays kept as a fallback, clients
   sometimes relayed campus-to-campus traffic through Singapore. It stays encrypted, but this is a
   latency and data-residency question for IT (request U6).

3. **The direct-connection share fell short** (44–58 % against an 80 % target). Two reasons:
   - Lab PCs behind one NAT all use UDP port 41641, so the NAT gives later ones a random port per
     destination. A real lab will see the same. Ask IT whether the lab NAT is endpoint-independent, or
     give each PC its own `--port`.
   - The simulated laptop clients ran in Docker, which adds an extra NAT. This part is an artifact of
     the rehearsal.

4. **The campus firewall setting changes the outcome a lot.** With UDP blocked, everything crossing the
   firewall was relayed, at 1–4 ms on campus. Off campus, with only port 443 allowed, everything was
   relayed at 27–37 ms. When inbound WireGuard UDP was allowed, some paths went direct.

5. **The policy has no rule for a user's own devices.** alice's home machine could not reach alice's
   laptop. Decide whether that is intended; if not, add an `autogroup:self` rule.

6. **Enrolment is fast** (seconds once the package is installed), and **revocation is near-instant**
   (3–5 s, against a 60 s target).

7. **Disaster recovery is quick** if the noise and DERP private keys are in the backup: a new server came
   up from the nightly backup and every node reconnected in about a minute.

8. **Practical gotchas met along the way:**
   - Caddy treats `.home.arpa` names as private and silently uses its own CA unless the ACME issuer is
     set explicitly. The same may happen with any internal university domain.
   - Clients cache trusted CAs when `tailscaled` starts, so restart it after installing a new root.
   - In Headscale 0.29, tagged lab PCs belong to their tags, not to a user, and pre-auth keys take a
     numeric user ID.
   - Restoring with restic from a read-only backup needs `--no-lock`.

**Not covered by the rehearsal:** Windows lab PCs, 15-PC scale, university SSO (OIDC), subnet routers,
upgrade rehearsal, the user survey, and the full 4-week (planned 7-day) run.
