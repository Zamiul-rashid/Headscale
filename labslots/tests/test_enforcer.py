import json

from conftest import MON_10, MON_21, TUE_03, Clock, FakeHeadscale, FakeSSH, nodes, seed

from labslots.enforcer import Enforcer


def make(db, when, hs=None, ssh=None):
    return Enforcer(db, hs or FakeHeadscale(nodes()), ssh or FakeSSH(), Clock(when))


def last_policy(hs):
    """Parse the newest policy written, skipping its // header lines."""
    return json.loads("\n".join(l for l in hs.policies[-1].splitlines() if not l.startswith("//")))


def test_day_slot_grants_group_a_only(db):
    seed(db)
    hs = FakeHeadscale(nodes())
    rep = make(db, MON_10, hs).reconcile()
    p = last_policy(hs)
    srcs = [g["src"] for g in p["grants"]]
    assert ["group:thesis-a"] in srcs and ["group:thesis-b"] not in srcs
    assert rep.policy_changed and not rep.errors


def test_night_after_midnight_still_monday_night(db):
    seed(db)
    hs = FakeHeadscale(nodes())
    make(db, TUE_03, hs).reconcile()
    srcs = [g["src"] for g in last_policy(hs)["grants"]]
    assert ["group:thesis-b"] in srcs and ["group:thesis-a"] not in srcs


def test_pending_booking_has_no_effect(db):
    seed(db)
    hs = FakeHeadscale(nodes())
    from datetime import datetime
    make(db, datetime(2026, 10, 20, 10), hs).reconcile()  # Tuesday day: only a pending booking
    assert not any(g["src"][0].startswith("group:thesis") for g in last_policy(hs)["grants"])


def test_policy_not_rewritten_when_unchanged(db):
    seed(db)
    hs = FakeHeadscale(nodes())
    e = make(db, MON_10, hs)
    e.reconcile()
    e.reconcile()
    assert len(hs.policies) == 1
    e.reconcile(force=True)
    assert len(hs.policies) == 2


def test_fail_closed_when_set_policy_rejected(db):
    seed(db)
    hs = FakeHeadscale(nodes(), fail_set=1)
    rep = make(db, MON_10, hs).reconcile()
    assert rep.admins_only and rep.errors
    srcs = [g["src"] for g in last_policy(hs)["grants"]]
    assert ["group:thesis-a"] not in srcs and ["group:admins"] in srcs
    assert db.setting("applied_policy_sha") == ""  # retried next run


def test_cleanup_dry_run_then_real(db):
    seed(db)
    hs = FakeHeadscale(nodes())
    rep = make(db, MON_10, hs).reconcile()
    # Monday day: A in slot. Bob (B) is out of slot -> his device; alice has 3 devices, cap 2 -> oldest.
    assert sorted(rep.would_delete) == ["alice-old (alice@g.bracu.ac.bd, id 12)", "bob-laptop (bob@g.bracu.ac.bd, id 20)"]
    assert hs.deleted == []
    db.set_setting("device_cleanup", "1")
    rep = make(db, MON_10, hs).reconcile()
    assert sorted(hs.deleted) == ["12", "20"]
    # admins, tagged PCs and people not on any roster are never touched
    assert not {"2", "3", "30", "40"} & set(hs.deleted)


def test_ssh_switch_only_when_enabled_and_idempotent(db):
    seed(db)
    ssh = FakeSSH()
    e = make(db, MON_10, ssh=ssh)
    e.reconcile()
    assert ssh.calls == []  # global switch off
    db.set_setting("ssh_enforce", "1")
    e.reconcile()
    assert ssh.calls == [("100.64.0.2", "grp-thesis-a", "ssh-ed25519 AAAAA a@x")]  # pc-43 has switching off
    e.reconcile()
    assert len(ssh.calls) == 1  # already in desired state
    e.clock.dt = MON_21
    e.reconcile()
    assert ssh.calls[-1][:2] == ("100.64.0.2", "grp-thesis-b")


def test_ssh_failure_is_retried(db):
    seed(db)
    db.set_setting("ssh_enforce", "1")
    ssh = FakeSSH(ok=False)
    e = make(db, MON_10, ssh=ssh)
    rep = e.reconcile()
    assert rep.errors and db.one("SELECT last_error FROM pc_state")["last_error"]
    ssh.ok = True
    e.reconcile()
    assert len(ssh.calls) == 2 and db.one("SELECT last_error FROM pc_state")["last_error"] is None


def test_free_slot_switches_pc_to_nobody(db):
    from datetime import datetime
    seed(db)
    db.set_setting("ssh_enforce", "1")
    ssh = FakeSSH()
    make(db, datetime(2026, 10, 21, 10), ssh=ssh).reconcile()  # Wednesday: no bookings
    assert ssh.calls == [("100.64.0.2", None, "")]


def test_test_rotation_cycles_groups_on_one_pc(db):
    import json as _j
    from datetime import timedelta
    ids = seed(db)
    db.set_setting("test_rotation", _j.dumps({"pc_id": ids["p2"], "groups": [ids["a"], ids["b"]], "seconds": 60,
                                              "start": MON_10.isoformat(),
                                              "end": (MON_10 + timedelta(minutes=3)).isoformat()}))
    hs = FakeHeadscale(nodes())
    e = make(db, MON_10 + timedelta(seconds=10), hs)
    rep = e.reconcile()
    assert rep.rotation and {(b["group_name"], b["pc_name"]) for b in rep.active} == {("Thesis A", "pc-41"), ("Thesis A", "pc-43")}
    e.clock.dt = MON_10 + timedelta(seconds=70)          # second slot: B on pc-43, A keeps its real pc-41 booking
    rep = e.reconcile()
    assert ("Thesis B", "pc-43") in {(b["group_name"], b["pc_name"]) for b in rep.active}
    assert e.next_change() == MON_10 + timedelta(seconds=120)
    e.clock.dt = MON_10 + timedelta(minutes=4)            # rotation over: normal routine only
    rep = e.reconcile()
    assert rep.rotation is None and {b["pc_name"] for b in rep.active} == {"pc-41"}


def test_pcs_are_switched_in_parallel(db):
    import threading
    import time

    from conftest import MON_10, Clock, FakeHeadscale, nodes, seed

    from labslots.enforcer import Enforcer
    from labslots.headscale import Node
    from labslots.sshexec import SSHResult
    seed(db)
    db.set_setting("ssh_enforce", "1")
    ns = nodes()
    for k in range(3, 23):   # 20 more PCs, all ssh-enabled
        db.x("INSERT INTO pcs(name, tag, ssh_enabled) VALUES (?, ?, 1)", (f"pc-x{k}", f"tag:pc-x{k}"))
        ns.append(Node(id=str(500 + k), name=f"pc-x{k}", owner="", tags=[f"tag:pc-x{k}"], online=True,
                       ips=[f"100.64.2.{k}"]))

    class SlowSSH:
        def __init__(self):
            self.live, self.peak, self.lock = 0, 0, threading.Lock()

        def switch(self, host, account, keys=""):
            with self.lock:
                self.live += 1
                self.peak = max(self.peak, self.live)
            time.sleep(0.2)
            with self.lock:
                self.live -= 1
            return SSHResult(True, "ok")
    ssh = SlowSSH()
    rep = Enforcer(db, FakeHeadscale(ns), ssh, Clock(MON_10)).reconcile()
    assert len(rep.ssh) == 21 and not rep.errors       # pc-41 plus the 20 new ones
    assert ssh.peak == 10 and rep.ssh_seconds < 1.5     # 21 x 0.2 s one by one would take 4.2 s
