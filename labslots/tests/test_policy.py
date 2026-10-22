import json

import pytest

from labslots.policy import PolicyError, PolicyInput, build_policy, render


def inp(**kw):
    base = dict(admins=["boss@bracu.ac.bd"], groups={"thesis-a": ["alice@g.bracu.ac.bd"], "empty": []},
                pc_tags=["tag:pc-41", "tag:pc-43"], active=[("thesis-a", "tag:pc-41")])
    base.update(kw)
    return PolicyInput(**base)


def test_slot_grant_and_admin_and_scheduler():
    p = build_policy(inp())
    assert p["groups"] == {"group:admins": ["boss@bracu.ac.bd"], "group:thesis-a": ["alice@g.bracu.ac.bd"]}
    assert {"src": ["group:thesis-a"], "dst": ["tag:pc-41"], "ip": ["tcp:22"]} in p["grants"]
    assert {"src": ["group:admins"], "dst": ["tag:pc-41", "tag:pc-43"], "ip": ["*"]} in p["grants"]
    assert {"src": ["tag:scheduler"], "dst": ["tag:pc-41", "tag:pc-43"], "ip": ["tcp:22"]} in p["grants"]
    assert p["tagOwners"]["tag:scheduler"] == ["group:admins"]


def test_admins_only_drops_slot_grants_but_keeps_grants_key():
    p = build_policy(inp(), admins_only=True)
    assert not any(g["src"] == ["group:thesis-a"] for g in p["grants"])
    assert "grants" in p


def test_empty_policy_is_deny_all_not_allow_all():
    p = build_policy(PolicyInput(admins=[], groups={}, pc_tags=[], active=[]))
    assert p == {"grants": []}


def test_extra_grants_tags_get_owners():
    extra = [{"src": ["tag:jumphost"], "dst": ["tag:pc-41"], "ip": ["tcp:22"]},
             {"src": ["autogroup:member"], "dst": ["autogroup:self"], "ip": ["*"]}]
    p = build_policy(inp(extra_grants=extra))
    assert "tag:jumphost" in p["tagOwners"] and p["grants"][-1]["dst"] == ["autogroup:self"]


def test_inactive_group_or_unknown_pc_gets_nothing():
    p = build_policy(inp(active=[("thesis-a", "tag:pc-99"), ("empty", "tag:pc-41")]))
    assert all(not g["src"][0].startswith("group:thesis") and g["src"] != ["group:empty"] for g in p["grants"])


@pytest.mark.parametrize("bad", [dict(groups={"Bad Slug": []}), dict(pc_tags=["pc-41"]),
                                 dict(admins=["no-at-sign"]), dict(extra_grants=[{"src": ["x"]}])])
def test_validation(bad):
    with pytest.raises(PolicyError):
        build_policy(inp(**bad))


def test_render_is_hujson_with_header():
    text = render(build_policy(inp()), "line one\nline two")
    assert text.startswith("// line one\n// line two\n")
    json.loads(text.split("\n", 2)[2])
