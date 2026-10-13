# Headscale v0.29.3 reference notes (research agent, 2026-10-13)

## Version
v0.29.3 (tag commit 5aff68b5b9921db5ccb88013bb1740077ab872fb, released 2026-07-29). Read from raw.githubusercontent.com at that tag: config-example.yaml, CHANGELOG.md, docs/ref/{policy,tags,derp,registration,oidc,configuration,tls,dns,debug,api}.md, docs/ref/integration/reverse-proxy.md, docs/setup/upgrade.md, cmd/headscale/cli/*.go, hscontrol/{app,grpcv1,auth}.go, hscontrol/state/state.go, hscontrol/types/config.go, hscontrol/db/preauth_keys.go, hscontrol/derp/server/derp_server.go, hscontrol/policy/v2/{types,policy}.go and proto/headscale/v1/*.proto. All of it was also run: image docker.io/headscale/headscale:v0.29.3 (sha256:0e7f1c6e...) with this config.yaml and policy, `configtest` rc=0, `serve` started, DERP region and STUN came up, users/preauthkeys/policy check/SIGHUP exercised. Not tested: a real Tailscale client registering. Ownership of tagged-key nodes is from source (state.go), not from a live registration. Minimum Tailscale client is v1.80.0. Upgrade path is strict (CHANGELOG 0.29.0, docs/setup/upgrade.md): only 0.28.x -> 0.29.x, no skipping minors and no downgrade. A fresh install is unaffected.

## Config changes vs proposal
The proposal excerpt was not included in the task text, so I cannot diff against it. Below is the list of every key that was renamed or removed on the way to v0.29.3, with the source for each. Check the excerpt against this list. All are fatal at startup unless marked warning. Source: hscontrol/types/config.go (depr.* calls, lines ~528-559) and CHANGELOG.md.
RENAMED (old key used -> fatal if the new key is not used): acl_policy_path -> policy.path; dns_config.magic_dns -> dns.magic_dns; dns_config.base_domain -> dns.base_domain; dns_config.override_local_dns -> dns.override_local_dns; dns_config.nameservers -> dns.nameservers.global; dns_config.restricted_nameservers -> dns.nameservers.split; dns_config.domains -> dns.search_domains; dns_config.extra_records -> dns.extra_records.
REMOVED (fatal if set): dns.use_username_in_magic_dns and dns_config.use_username_in_magic_dns (removed 0.24); oidc.strip_email_domain and oidc.map_legacy_users (removed 0.26); randomize_client_port (removed 0.29.0; now the top-level "randomizeClientPort" field in the policy file); oidc.expiry (removed 0.29.0, use node.expiry).
DEPRECATED (warning only): ephemeral_node_inactivity_timeout -> node.ephemeral.inactivity_timeout.
Other config-affecting changes: 0.26: dns.nameservers.global must be non-empty when dns.override_local_dns is true or unset (it is true by default; satisfied here with 192.168.1.202); server_url and dns.base_domain must not be equal or one a suffix of the other (config.go isSafeServerURL; hs.uni.home.arpa vs lab.internal passes). 0.29.0: new keys node.expiry, node.routes.ha.*, trusted_proxies, auto_update.enabled, taildrop.enabled; tuning.* is commented out. The embedded-DERP keys derp.server.{enabled,region_id,region_code,region_name,verify_clients,stun_listen_addr,private_key_path,automatically_add_embedded_derp_region,ipv4,ipv6} and derp.{urls,paths,auto_update_enabled,update_frequency} are all current. derp.update_frequency default is 3h (was 24h before 0.27).

DEVIATIONS from "keep every other key at its example default":
1. derp.server.ipv4/ipv6: the example ships ACTIVE placeholders 198.51.100.1 and 2001:db8::1 (RFC 5737/3849 documentation addresses). I commented them out. Left active, clients would be told to reach the DERP at an unroutable address. Set them to the server's real LAN IPv4/IPv6 if you want the "stability" hint (docs/ref/derp.md); the DERP node hostname is already taken from server_url (derp_server.go GenerateRegion).
2. trusted_proxies is left at the default [] as instructed. With Caddy in front, headscale logs will show 127.0.0.1 as the client IP. docs/ref/integration/reverse-proxy.md recommends trusted_proxies: [127.0.0.1/32, ::1/128] together with header_up True-Client-IP/X-Real-IP in Caddy. This is optional logging hygiene only; I did not apply it because it changes a default.
3. grpc_listen_addr 127.0.0.1:50443 is kept with grpc_allow_insecure: false. Local CLI uses unix_socket (/var/run/headscale/headscale.sock), not this port. docs/ref/integration/reverse-proxy.md: gRPC may not be proxied.
4. metrics_listen_addr 0.0.0.0:9090 exposes /metrics and /debug on all interfaces. docs/ref/debug.md: keep it private; /debug has extra protection (localhost, debug key, or TS_ALLOW_DEBUG_IP) but /metrics is open. Firewall 9090 to the monitoring host only.
5. noise.private_key_path default already equals the requested path; tls_cert_path/tls_key_path stay "" because Caddy terminates TLS.
Verified by `diff config-example.yaml config.yaml` that ONLY these lines differ: server_url, metrics_listen_addr, derp.server.enabled, region_code, region_name, the ipv4/ipv6 lines, policy.path, dns.base_domain, dns.nameservers.global (1.1.1.1/1.0.0.1/2606:4700:4700::1111/::1001 replaced by 192.168.1.202).
Startup log with this config (verified): 'WRN listening without TLS but ServerURL does not start with http://' is expected behind a TLS-terminating proxy (reverse-proxy.md). DERP node log shows HostName:hs.uni.home.arpa DERPPort:443 STUNPort:3478 IPv4/IPv6 empty. If the DNS name lab.internal is not delegated, nothing else is needed. 192.168.1.202 must be reachable by clients through the tailnet or LAN, since override_local_dns forces it onto every client.


## Policy notes
Verified by running `headscale policy check -f policy.hujson` against v0.29.3 with users admin1, alice and bob: "Policy is valid" rc=0. `configtest` rc=0 and a SIGHUP reload were also OK.
USER NAME FORMAT (docs/ref/oidc.md "Reference a user in the policy"; policy/v2/types.go Username): every user token in the policy must contain a single '@'. For a plain Headscale username append it: user `alice` is written `alice@`. A bare `admin1` is rejected: 'username must contain @, got: "admin1"' (verified, both with policy check and configtest, and a bad file at startup is fatal). The Headscale username itself must not end with '@' (docs/ref/registration.md footnote 1). Resolution (resolveUser): trailing '@' is stripped, then matched against ProviderIdentifier first, then Email or Name. Duplicate matches make the policy fail to load ('multiple users found'; policy.go validateUserReferences). A user that does not exist is tolerated at load (only logged or yields no addresses), so create admin1, alice, bob with `headscale users create` or their rules match nothing. Group names must start with 'group:', tags with 'tag:' and be lowercase.
TAGS MUST BE DEFINED: using a tag in acls without a tagOwners entry fails ('tag not found' / ErrUndefinedTagReference). Both tag:labpc and tag:gpu are defined. tag:gpu has no ACL rule; only admins reach it via *:*.
DO CLI PREAUTHKEY TAGS BYPASS tagOwners? YES. Verified empirically: `headscale preauthkeys create --tags tag:undefinedtag -e 1h` succeeded although tag:undefinedtag is not in tagOwners. Source: grpcv1.go CreatePreAuthKey calls only validateTag (prefix 'tag:', lowercase, no spaces); db/preauth_keys.go CreatePreAuthKey only checks the 'tag:' prefix; neither calls the policy manager. At registration the tags are copied from the key (state.go createAndSaveNewNode: Tags = PreAuthKey.Proto().GetAclTags()) with no NodeCanHaveTag check. tagOwners is only enforced for tags the CLIENT requests via `tailscale up --advertise-tags` (state.go validateRequestTags uses NodeCanHaveTag / UserCanHaveTag). The reverse also holds: a client registering WITH a preauthkey and --advertise-tags is rejected ('requested tags ... are invalid or not permitted'; the key's tags are authoritative). Consequence: whoever can run the headscale CLI (root or the socket group) can mint any tag; tagOwners does not constrain admins using the CLI. Operationally, only create keys with tag:labpc or tag:gpu; an undefined tag creates a node that no ACL can reference.
DO TAGGED NODES STILL BELONG TO THE CREATING USER? NO. docs/ref/registration.md (Identity model): 'a tagged node is owned by a tag... Tagged devices are grouped under the special user tagged-devices'; docs/ref/tags.md says the same. Code: state.go createAndSaveNewNode, for a tagged key 'Tagged nodes are owned by their tags, not a user. UserID is intentionally left nil' and expiry is set to nil (tagged nodes never expire; the node.expiry default also exempts them). `nodes list` shows User=tagged-devices and the Tags column. Since v0.28.0 (CHANGELOG 'Tags as identity') tags and user ownership are mutually exclusive. If `--user <id>` is also passed to preauthkeys create, it only records who CREATED the key (db/preauth_keys.go comment 'For tagged keys, uid tracks created by'); the node still gets no user. Re-registering a tagged node with a DIFFERENT tagged key now applies the new key's tags (0.29.3 #3394). Converting a tagged node back to personal: `tailscale up --login-server <URL> --advertise-tags= --force-reauth` then `headscale auth register --user <USER> --auth-id <ID>` (tags.md).
RULE SEMANTICS IN 0.29 (CHANGELOG 0.29.0 BREAKING): '*' in acl src/dst now means the tailnet ranges 100.64.0.0/10 and fd7a:115c:a1e0::/48, NOT all IPs; use autogroup:danger-all (src only) for everything. So admins -> *:* reaches every tailnet node including tagged ones, but not LAN addresses behind subnet routers (use explicit CIDRs for those). Identity aliases (users, groups, tags) now resolve to both v4 and v6 addresses. Because tagged nodes belong to no user, researchers' PERSONAL nodes (alice/bob) are the sources and tag:labpc nodes the destinations. Rules are one-directional: the dst nodes' return traffic is allowed by connection tracking; labpc nodes cannot initiate to researchers. Zero or empty destination ports are rejected (0.27). Port list syntax 'tag:labpc:22,3389,5900,8888' is accepted (policy check passed).
ACLS VS GRANTS: docs/ref/policy.md says ACLs are legacy and recommends grants ('grants' with 'ip'), but ACLs remain supported and can be mixed with grants in one file (0.29.0). I kept `acls` as requested. Equivalent grant: {"src":["group:researchers"],"dst":["tag:labpc"],"ip":["22,3389,5900,8888"]}. If you omit both acls and grants you get allow-all; an empty `"grants": []` gives deny-all (policy.md).
RELOAD: see cli_cheatsheet. File mode needs SIGHUP; `policy set` is rejected in file mode. After editing, run `headscale policy check -f` first (needs a running server) so a bad edit does not just log an error on SIGHUP. Optional beta feature: a `tests` block (evaluated on SIGHUP/check, with --bypass for offline) can assert e.g. researchers cannot reach tag:labpc:80; not added to avoid beta behaviour in the base policy.


## CLI cheatsheet
All commands verified against image headscale/headscale:v0.29.3 (running server, unix socket). Add `-c /etc/headscale/config.yaml` if the config is elsewhere. Run as a user that can read the socket (unix_socket_permission 0770) or as root. Source: cmd/headscale/cli/*.go.

GLOBAL FLAGS: -c/--config, -o/--output ('' | json | json-line | yaml), --force (skips confirmation prompts).

OUTPUT FORMAT WARNING (verified): -o json uses Go encoding/json on protobuf structs, so keys are snake_case and zero values are OMITTED. `online:false` is absent, `tags` is absent when empty, timestamps are {"seconds":N,"nanos":N}. An empty `nodes list -o json` prints `null`, not `[]`. In jq use: `.[] | {id, name: .given_name, online: (.online // false), tags: (.tags // [])}` and `(. // [])`. Source: utils.go formatOutput; node.proto/preauthkey.proto/user.proto.

USERS (names must NOT end with '@'; the policy adds the '@'):
  headscale users create admin1
  headscale users create alice
  headscale users create bob
  headscale users list -o json                      # fields: id (number), name, created_at, display_name, email, provider_id, provider, profile_pic_url
  headscale users list -n alice -o json             # filter by name; also -i <id>, -e <email> (one filter at most)
  headscale users rename -i <id> -r <newname>       # --new-name/-r required
  headscale users destroy -i <id> --force           # also accepts -n <name>

PREAUTHKEYS (verified: `--user/-u` takes the NUMERIC user ID, not the name; `-u admin1` fails with strconv.ParseUint). Since v0.28.0 --user is optional when --tags is given (it then only records the creator). A key needs either --tags or --user, otherwise: "auth-key must be either tagged or owned by user".
  # tagged, reusable, 24h key for lab PCs (no user needed). Prints ONLY the key; save it, it is shown once:
  headscale preauthkeys create --tags tag:labpc --reusable --expiration 24h
  headscale preauthkeys create --tags tag:labpc,tag:gpu -e 90d       # --tags is a StringSlice: comma list or repeated flag
  headscale preauthkeys create --tags tag:labpc --reusable -e 24h -o json   # JSON: id, key (full hskey-auth-..., only here), reusable, ephemeral, used, expiration, created_at, acl_tags [, user]
  # personal (user-owned) key; -u is the numeric ID from `users list`:
  headscale preauthkeys create -u 2 -e 1h
  headscale preauthkeys create --tags tag:labpc --ephemeral -e 1h    # also --reusable (default false), -e/--expiration default 1h, accepts 30m/24h/90d
  headscale preauthkeys list -o json                  # key shown as hskey-auth-<prefix>-*** only; fields id, key, reusable, ephemeral, used, expiration, created_at, acl_tags, user
  headscale preauthkeys expire --id <ID>              # --id is required; 0 gives "missing --id parameter"
  headscale preauthkeys delete --id <ID>              # a key already used by a node cannot be deleted (CHANGELOG 0.25.0)
  Aliases: preauthkey, authkey, pre. Tags are validated only for the 'tag:' prefix, lowercase and no spaces (grpcv1.go validateTag). Key format hskey-auth-<12-char prefix>-<secret>, bcrypt-hashed (0.28.0).

NODES:
  headscale nodes list -o json                        # JSON fields per node: id, machine_key, node_key, disco_key, ip_addresses[], name (hostname), given_name (MagicDNS label), user{id,name,...} (absent for tagged nodes), last_seen, expiry, pre_auth_key{...}, created_at, register_method, online (omitted when false), approved_routes, available_routes, subnet_routes, tags[]
  headscale nodes list -u alice -o json               # filter by user (name) with -u/--user
  headscale nodes list                                # table columns: ID Hostname Name MachineKey NodeKey User Tags "IP addresses" Ephemeral "Last seen" Expiration Connected Expired
  headscale nodes expire -i <ID>                      # -i/--identifier REQUIRED; expires NOW (logs the node out, node stays in DB). Optional -e <RFC3339> or -d/--disable (never expire)
  headscale nodes delete -i <ID> --force              # removes the node; without --force it prompts
  headscale nodes rename -i <ID> <NEW_NAME>
  headscale nodes tag -i <ID> -t tag:labpc,tag:gpu    # replaces tags; converts a personal node to tagged (owner becomes 'tagged-devices')
  headscale nodes approve-routes -i <ID> -r 10.0.0.0/8
  headscale nodes list-routes
  headscale nodes backfillips
  `headscale nodes register` is DEPRECATED in 0.29; use: headscale auth register --auth-id <ID> --user <USER>   (also: headscale auth approve|reject --auth-id <ID>)

CONFIG / POLICY CHECKS:
  headscale configtest                                # EXISTS. Runs the same init as `serve`: opens/creates the DB and key files (needs write access to /var/lib/headscale; run as the headscale user, not as another user, or it can leave root-owned files), parses config AND loads the policy file. Verified: bad policy -> "configuration error: ... username must contain @" rc=1; good -> rc=0, silent.
  headscale policy check -f /etc/headscale/policy.hujson     # EXISTS (since 0.26). Default: gRPC to the RUNNING server, resolves users/nodes live, prints "Policy is valid" (verified rc=0; unknown tag -> 'tag not found: "tag:nope"' rc=1)
  headscale policy check -f policy.hujson --bypass-grpc-and-access-database-directly   # offline check against the DB; stop headscale first; prompts unless --force; the only mode that evaluates `tests`/`sshTests` blocks (beta)
  headscale policy get                                # prints the policy
  headscale policy set -f ...                         # DOES NOT WORK in file mode (verified): "update is disabled for modes other than 'database'"
  headscale version
  headscale health                                    # exists (prints nothing, rc=0 when healthy)

POLICY RELOAD IN FILE MODE (policy.mode: file): there is no CLI reload. Send SIGHUP: `sudo systemctl reload headscale` or `sudo kill -HUP $(pidof headscale)` (docs/ref/policy.md; app.go signal handler, no-op if policy is empty). Verified in the container logs: 'Received SIGHUP, reloading ACL policy'; an invalid file logs 'ERR reloading policy error=...' and the previously loaded policy stays active; the process keeps running. At startup an invalid policy file is fatal (configtest rc=1 / serve refuses to start). Policy `tests` are also run on SIGHUP (beta).

SERVICE: headscale serve   (config /etc/headscale/config.yaml by default, or -c / HEADSCALE_CONFIG)
Note: with `-o json`/`yaml`/`json-line` the CLI disables its own log output (root.go), so stdout stays parseable.


## Caddy
Source: docs/ref/integration/reverse-proxy.md (v0.29.3; labelled 'community documentation, not verified by Headscale developers'), app.go routes, and the verified server startup.
1. Nothing special is required for WebSockets or DERP over HTTPS with Caddy. The page states Caddy 'will automatically provision a certificate for your domain, force HTTPS, and proxy WebSocket connections'. The Tailscale control protocol upgrade is a POST with 'Upgrade: tailscale-control-protocol', which Caddy's reverse_proxy passes through without config (Nginx and Apache need explicit settings; Envoy/Istio need an upgrade_type). The DERP endpoint (/derp, /derp/probe, /derp/latency-check, /bootstrap-dns) is served by headscale on the same listen_addr as everything else (app.go lines ~576-580), so the single reverse_proxy covers it. 0.29.2 fixed /ts2021 rejecting the WebSocket GET upgrade (#3359), so 0.29.3 is fine.
2. Docs-recommended Caddyfile (reverse-proxy.md), adapted to this deployment:
http://hs.uni.home.arpa {
	# Tailscale captive portal detection
	handle /generate_204 {
		respond 204
	}
	handle * {
		redir https://{host}{uri}
	}
}
hs.uni.home.arpa {
	reverse_proxy 127.0.0.1:8080 {
		header_up True-Client-IP {remote_host}
		header_up X-Real-IP {remote_host}
	}
}
The header_up lines only matter if headscale has trusted_proxies set (see config_key_changes_vs_proposal item 2); otherwise headscale ignores them. Port 80 handling and /generate_204 are in the docs' example; HTTP->HTTPS redirect applies to everything else.
3. Not proxied by Caddy: STUN udp/3478 (reverse-proxy.md Limitations: 'STUN requires udp/3478 to be served publicly'; the embedded DERP's STUN is exposed directly by headscale on 0.0.0.0:3478, verified in the log 'stun server started at [::]:3478'), metrics 9090 and gRPC 50443 ('gRPC may not be proxied'). Open tcp/443 (and tcp/80 for the redirect) plus udp/3478 on the host firewall.
4. Headscale-side requirements that match Caddy terminating TLS: server_url https://hs.uni.home.arpa, tls_cert_path and tls_key_path left empty, listen_addr 127.0.0.1:8080 (matches the docs' base config). Expected startup warning: 'listening without TLS but ServerURL does not start with http://' (explicitly called out as expected in reverse-proxy.md).
5. Internal-CA caveat (not in the docs, derived from the setup): hs.uni.home.arpa is not a public name, so Caddy cannot use Let's Encrypt HTTP/TLS challenges for it and will use its internal CA or a cert you provide. Every Tailscale client verifies the HTTPS certificate for both the control URL and the DERP hostname (the DERP node HostName is hs.uni.home.arpa, DERPPort 443). Install the Caddy root CA (or your campus CA) in each client's OS trust store, or neither registration nor DERP will work. Cloudflare Proxy/Tunnel is unsupported in front of headscale (reverse-proxy.md: no WebSocket POST support), so do not put it in front.
6. The name hs.uni.home.arpa must resolve for clients to the Caddy host (the DNS at 192.168.1.202 or hosts entries), because DERP clients connect to it by name; no ipv4/ipv6 hint is configured.


## DERP
Sources: config-example.yaml (v0.29.3), docs/ref/derp.md, hscontrol/types/config.go derpConfig(), hscontrol/derp/server/derp_server.go GenerateRegion(), hscontrol/app.go.
1. Is TLS terminated by the proxy OK? Yes, with the right server_url. The example says 'The Headscale server_url defined above MUST be using https, DERP requires TLS to be in place'. The code does not enforce it (config.go only requires server_url to start with http:// or https://), but the embedded DERP is advertised to clients using the scheme and host of server_url: derp_server.go GenerateRegion parses server_url, takes the hostname, and uses port 443 if the scheme is https (80 if http), setting no explicit CertName. Verified in the startup log with this config: 'HostName:hs.uni.home.arpa DERPPort:443 STUNPort:3478 ... CanPort80:false'. So clients open https://hs.uni.home.arpa:443/derp, and Caddy must terminate TLS there (reverse-proxy.md: TLS may be handled by the proxy; tls_cert_path/tls_key_path empty). If the proxy listens on a non-443 port, include it in server_url so DERPPort follows. The /derp handler lives on the same listen_addr (app.go).
2. server_url vs DERP key rules: derp.server.private_key_path must differ from noise.private_key_path or startup fails (app.go: 'DERP server private key and noise private key are the same'); with this config the key is auto-created if missing (verified). stun_listen_addr is mandatory when derp.server.enabled is true (config.go: log.Fatal 'derp.server.stun_listen_addr must be set'); STUN must be reachable on udp/3478 directly; it cannot go through Caddy (reverse-proxy.md Limitations). It is shown as listening on [::]:3478.
3. ipv4/ipv6 fields: optional (docs/ref/derp.md: 'you should configure the public IPv4 and public IPv6 address of your Headscale server for improved connection stability', particularly when using an exit node when DNS is not working). They are copied verbatim into the DERPNode IPv4/IPv6 (derp_server.go). With them unset, clients rely on DNS for hs.uni.home.arpa. The example's active values 198.51.100.1 and 2001:db8::1 are documentation placeholders; I commented them out. If you want them, use the server's LAN IPv4 (not a documentation range); with IPv4 set but no IPv6, leave ipv6 out (an empty string is the default).
4. region_id 999 is the example default. The local region replaces any same-ID region from derp.urls. The embedded region is merged into the Tailscale default map from derp.urls (docs/ref/derp.md: 'Once enabled, Headscale's embedded DERP is added to the list of free-to-use DERP servers offered by Tailscale Inc'). That means clients on a campus network with internet may also choose Tailscale's public DERPs; derp.urls: [] would force only the embedded DERP, but docs warn that is a single point of failure, and you asked to keep the default URL. Also derp.auto_update_enabled true needs outbound HTTPS to controlplane.tailscale.com every 3h; an unreachable controlplane at startup is fatal if the resulting DERP map is empty (app.go errEmptyInitialDERPMap), but the embedded region guarantees a non-empty map here.
5. verify_clients: true (the default): the embedded DERP only relays for nodes known to headscale (derp.md; app.go registers a verify transport and POST /verify). Default and unchanged.
6. automatically_add_embedded_derp_region: true is the default; set false only with a custom derp.paths file; setting false without paths is fatal (config.go).
7. Check: `tailscale debug derp-map` and `tailscale debug derp campus` from a client (derp.md; 'headscale' in the docs is the default region code, here it is 'campus'). Limitation (derp.md): the embedded DERP does not provide /generate_204 on port 80 for captive-portal checks; Caddy's example block handles /generate_204 itself. verify_clients also means DERP traffic from machines not registered yet is refused.
8. Firewall summary: tcp/443 (via Caddy) for control plus DERP, udp/3478 STUN straight to headscale, tcp/80 optional for the redirect. Node-to-node direct WireGuard (udp/41641 or random) is unaffected.


