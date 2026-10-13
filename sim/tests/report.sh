#!/usr/bin/env bash
# Proposal §11 success-criteria report from the result CSVs.   tests/report.sh <results-dir>  -> <dir>/report.md
set -euo pipefail
D=${1:?usage: $0 <results-dir>}
OUT=$D/report.md
has() { [ -s "$D/$1" ]; }
pf() { awk -v v="$1" -v t="$2" -v op="$3" 'BEGIN{ if (v=="" || v=="NA") {print "NO DATA"; exit}
  ok = (op=="ge") ? (v+0 >= t+0) : (v+0 <= t+0); print ok ? "PASS" : "FAIL" }'; }
rows=()
add() { rows+=("| $1 | $2 | $3 | $4 |"); }

# Lab PCs online (last soak sample) and enrolment time (lab-* rows only)
if has soak.csv; then last=$(tail -1 "$D/soak.csv"); on=$(cut -d, -f3 <<<"$last"); tot=$(cut -d, -f2 <<<"$last")
  add "Nodes online (last soak sample)" "all" "$on/$tot" "$([ "$on" = "$tot" ] && echo PASS || echo FAIL)"
else add "Nodes online (last soak sample)" "all" "—" "NO DATA"; fi
m=$(has enrolment.csv && awk -F, '/^lab-/{s+=$2;n++} END{if(n) printf "%.0f", s/n}' "$D/enrolment.csv" || true)
add "Mean enrolment time per lab PC" "≤ 600 s" "${m:-—} s" "$(pf "${m:-}" 600 le)"

# Soak coverage: enough samples, long enough, no long gaps (SOAK_DAYS, default 7)
if has soak.csv; then
  read -r ns span gap < <(awk -F, 'NR>1{cmd="date -d \"" $1 "\" +%s"; cmd | getline t; close(cmd); n++;
      if (n==1) f=t; else if (t-p > g) g=t-p; p=t} END{printf "%d %.0f %.1f\n", n, (p-f)/3600, g/3600}' "$D/soak.csv")
  need=$(( ${SOAK_DAYS:-7} * 24 * 9 / 10 ))
  add "Soak coverage" "≥ $need h, gaps ≤ 2 h" "$ns samples over $span h, longest gap $gap h" \
    "$(awk -v s="$span" -v n="$need" -v g="$gap" 'BEGIN{print (s>=n && g<=2) ? "PASS" : "FAIL"}')"
else add "Soak coverage" "≥ $(( ${SOAK_DAYS:-7} * 24 * 9 / 10 )) h" "—" "NO DATA"; fi
# Uptime and certificate validity from soak samples
if has soak.csv; then
  up=$(awk -F, 'NR>1{n++; if($4=="ok") k++} END{if(n) printf "%.1f", 100*k/n}' "$D/soak.csv")
  badcert=$(awk -F, 'NR>1 && $5+0<=0' "$D/soak.csv" | wc -l)
  badts=$(awk -F, 'NR>1 && $7!="1"' "$D/soak.csv" | wc -l)
else up= badcert= badts=; fi
add "Uptime (control server health checks)" "≥ 99 %" "${up:-—} %" "$(pf "${up:-}" 99 ge)"
add "TLS certificate valid in every sample" "0 expired" "${badcert:-—} expired" "$([ -z "${badcert}" ] && echo 'NO DATA' || { [ "$badcert" -eq 0 ] && echo PASS || echo FAIL; })"
add "Hosted tailnets untouched (enigma)" "every sample" "${badts:-—} changed" "$([ -z "${badts}" ] && echo 'NO DATA' || { [ "$badts" -eq 0 ] && echo PASS || echo FAIL; })"

# Direct share (open mode, reachable pairs only)
ds=$(has connectivity-open.csv && awk -F, 'NR>1 && $3=="direct"{d++} NR>1 && $3 ~ /^derp/{r++} END{if(d+r) printf "%.0f", 100*d/(d+r)}' "$D/connectivity-open.csv" || true)
add "Direct (non-relayed) peer pairs, open mode" "≥ 80 %" "${ds:-—} %" "$(pf "${ds:-}" 80 ge)"

# Latency / throughput: worst numeric pair
# same-room = two CTs on one Proxmox bridge (memory copy, ~54 Gbit/s): not a LAN baseline, shown separately
lat=$(has perf-open.csv && awk -F, 'NR>1 && $1!="same-room" && $7!="NA" && $7!=""{if(m=="" || $7+0>m+0) m=$7} END{print m}' "$D/perf-open.csv" || true)
thr=$(has perf-open.csv && awk -F, 'NR>1 && $1!="same-room" && $4!="NA" && $4!=""{if(m=="" || $4+0<m+0) m=$4} END{print m}' "$D/perf-open.csv" || true)
add "Added latency, tailnet vs LAN (worst pair)" "≤ 5 ms" "${lat:-—} ms" "$(pf "${lat:-}" 5 le)"
add "Throughput, tailnet / LAN (worst pair)" "≥ 0.70" "${thr:-—}" "$(pf "${thr:-}" 0.70 ge)"

acl=$(has acl.csv && awk -F, 'NR>1 && $6!="skipped"{n++; if($6=="yes") k++} END{if(n) printf "%.0f", 100*k/n}' "$D/acl.csv" || true)
askip=$(has acl.csv && awk -F, 'NR>1 && $6=="skipped"' "$D/acl.csv" | wc -l || echo 0)
add "ACL tests passed" "100 %" "${acl:-—} % (${askip} skipped)" "$(pf "${acl:-}" 100 ge)"
rv=$(has revocation.csv && awk -F, 'NR>1 && $1!="expired-key"{if($2=="timeout"){m=99999} else if($2+0>m+0) m=$2} END{print m}' "$D/revocation.csv" || true)
add "Revocation time (worst case)" "≤ 60 s" "${rv:-—} s" "$(pf "${rv:-}" 60 le)"
rto=$(has dr.csv && awk -F, 'NR==2{print $1}' "$D/dr.csv" || true)
add "Backup restore RTO" "≤ 7200 s" "${rto:-—} s" "$(pf "${rto:-}" 7200 le)"
add "User satisfaction (survey)" "≥ 4.0" "N/A (not simulated)" "N/A"
inc=$( [ -s "$D/incidents.txt" ] && grep -cv '^\s*$' "$D/incidents.txt" || echo 0)
add "Security incidents" "0" "$inc" "$([ "$inc" -eq 0 ] && echo PASS || echo FAIL)"

{
  echo "# hs-sim pilot rehearsal — success criteria (proposal §11)"
  echo
  echo "| Metric | Target | Measured | Result |"
  echo "|---|---|---|---|"
  printf '%s\n' "${rows[@]}"
  echo
  echo "## Flagged soak samples"
  if has soak.csv; then
    awk -F, 'NR>1 && ($4!="ok" || $5+0<=0 || $7!="1") {
      printf "- %s:", $1; if ($4!="ok") printf " hs_health=%s", $4; if ($5+0<=0) printf " cert_hours_left=%s", $5;
      if ($7!="1") printf " enigma_tailnet_ok=%s", $7; print "" }' "$D/soak.csv"
  fi
  if has perf-open.csv && grep -q '^same-room,' "$D/perf-open.csv"; then
    echo; echo "## Informational: same-room pair (not graded)"; echo
    echo "Two CTs on one Proxmox bridge compare a memory copy with WireGuard, so it is not a LAN baseline:"
    awk -F, '$1=="same-room"{printf "same-room: LAN %s Mbit/s, tailnet %s Mbit/s, added latency %s ms\n", $2, $3, $7}' "$D/perf-open.csv"
  fi
  if has outage.csv; then
    echo; echo "## Control-plane outage and reboot"; echo; echo '| Case | Metric | Value | Result |'; echo '|---|---|---|---|'
    awk -F, 'NR>1{printf "| %s | %s | %s | %s |\n", $1, $2, $3, $4}' "$D/outage.csv"
  fi
  echo
  echo "## Not covered by the simulation"
  echo "- Windows lab PCs (MSI + \`--unattended\`): no Windows device in the home lab."
  echo "- 15-PC scale: 3 lab PCs (lab-a-01 on server0, lab-b-01/02 in room B)."
  echo "- University SSO (OIDC), subnet router, client/server upgrade rehearsal, Phase 0 approvals."
  echo "- User satisfaction survey; 4-week pilot shortened to a soak run."
  echo "- Researcher clients run in Docker on hosts that already use a hosted tailnet (extra NAT hop)."
  [ -s "$D/notes.md" ] && { echo; echo "## Findings"; echo; sed 1d "$D/notes.md"; }
} > "$OUT"
echo "$OUT"
