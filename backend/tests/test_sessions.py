"""End to end: simulated toy runs a maths session; the parent sees an honest report."""

from conftest import add_child, claim, dev_auth, make_device, new_id


def _run_maths(client, cred, answers=None, sid=None):
    sid = sid or "sess-" + new_id()[:12]
    r = client.post("/v1/device/sessions", headers=dev_auth(cred),
                    json={"client_session_id": sid, "activity_key": "maths"})
    assert r.status_code == 200, r.text
    first = r.json()
    return sid, first


def _setup(client, alice, transcripts=False):
    if transcripts:
        client.patch("/v1/me", headers=alice, json={"store_transcripts": True})
    child = add_child(client, alice)
    device = make_device(client)
    _c, cred = claim(client, alice, device)
    return child, cred


def _answer_all(client, cred, sid, alice, pattern):
    """pattern(index) -> (transcript, quality). Runs until done."""
    from app import db as dbm
    from app.models import LearningSession

    i = 0
    while True:
        with dbm._SessionLocal() as db:
            from sqlalchemy import select

            s = db.scalar(select(LearningSession).where(LearningSession.client_session_id == sid))
            state = s.state
        item = state["items"][state["index"]]
        transcript, quality = pattern(i, item)
        r = client.post(f"/v1/device/sessions/{sid}/turns", headers=dev_auth(cred),
                        json={"turn_id": f"t{i}", "transcript": transcript,
                              "audio_quality": quality, "stt_confidence": 0.9})
        assert r.status_code == 200, r.text
        i += 1
        if r.json()["done"]:
            return r.json()


def test_maths_session_produces_parent_report(client, alice):
    child, cred = _setup(client, alice)
    sid, first = _run_maths(client, cred)
    assert "What is" in first["say"]

    def pattern(i, item):
        if i == 0:
            return item["expected"], "good"  # correct
        if i in (1, 2):
            return str(int(item["expected"]) + 1), "good"  # wrong twice -> revisit
        if i in (3, 4, 5):
            return "", "noisy"  # never judged
        return item["expected"], "good"

    final = _answer_all(client, cred, sid, alice, pattern)
    assert final["state"] == "summary"

    page = client.get(f"/v1/sessions?child_id={child['id']}", headers=alice).json()
    s = page["items"][0]
    assert s["status"] == "completed" and s["activity_key"] == "maths"
    assert s["needs_practice"] == 1 and s["uncertain"] == 1
    assert s["correct"] >= 1
    assert "couldn't assess" in s["summary"]

    detail = client.get(f"/v1/sessions/{s['id']}", headers=alice).json()
    assert detail["transcripts_available"] is False
    assert detail["turns"] == []
    # Practised questions are visible; what the child said is not stored by default.
    assert all(a["response_text"] is None for a in detail["assessments"])
    assert {a["outcome"] for a in detail["assessments"]} == {"correct", "needs_practice",
                                                             "uncertain"}
    assert all(a["source"] == "maths.deterministic" for a in detail["assessments"])


def test_transcripts_only_when_parent_opts_in(client, alice):
    _child, cred = _setup(client, alice, transcripts=True)
    sid, _ = _run_maths(client, cred)
    _answer_all(client, cred, sid, alice, lambda i, item: (item["expected"], "good"))
    s = client.get("/v1/sessions", headers=alice).json()["items"][0]
    detail = client.get(f"/v1/sessions/{s['id']}", headers=alice).json()
    assert detail["transcripts_available"] is True
    assert detail["turns"][0]["speaker"] == "toy"


def test_duplicate_session_start_and_turn_are_idempotent(client, alice):
    _child, cred = _setup(client, alice)
    sid, first = _run_maths(client, cred)
    _sid, again = _run_maths(client, cred, sid=sid)
    assert first == again
    body = {"turn_id": "dup", "transcript": "", "audio_quality": "silent"}
    r1 = client.post(f"/v1/device/sessions/{sid}/turns", headers=dev_auth(cred), json=body)
    r2 = client.post(f"/v1/device/sessions/{sid}/turns", headers=dev_auth(cred), json=body)
    assert r1.json() == r2.json()
    s = client.get("/v1/sessions", headers=alice).json()["items"]
    assert len(s) == 1
    detail = client.get(f"/v1/sessions/{s[0]['id']}", headers=alice).json()
    assert len(detail["assessments"]) == 1


def test_session_delete_and_pagination(client, alice):
    _child, cred = _setup(client, alice)
    for _ in range(5):
        sid, _ = _run_maths(client, cred)
        client.post(f"/v1/device/sessions/{sid}/end", headers=dev_auth(cred))
    p1 = client.get("/v1/sessions?limit=2", headers=alice).json()
    p2 = client.get(f"/v1/sessions?limit=2&cursor={p1['next_cursor']}", headers=alice).json()
    p3 = client.get(f"/v1/sessions?limit=2&cursor={p2['next_cursor']}", headers=alice).json()
    ids = [s["id"] for s in p1["items"] + p2["items"] + p3["items"]]
    assert len(ids) == len(set(ids)) == 5 and p3["next_cursor"] is None
    assert p1["items"][0]["status"] == "ended_early"
    assert client.delete(f"/v1/sessions/{ids[0]}", headers=alice).status_code == 204
    assert client.get(f"/v1/sessions/{ids[0]}", headers=alice).status_code == 404
    assert client.get("/v1/sessions?cursor=garbage", headers=alice).status_code == 400


def test_session_requires_child_profile(client, alice):
    device = make_device(client)
    _c, cred = claim(client, alice, device)
    r = client.post("/v1/device/sessions", headers=dev_auth(cred),
                    json={"client_session_id": "abcdefgh", "activity_key": "maths"})
    assert r.status_code == 409 and r.json()["error"]["code"] == "no_active_child"


def test_disabled_activity_is_refused(client, alice):
    child, cred = _setup(client, alice)
    prefs = client.get(f"/v1/children/{child['id']}/preferences", headers=alice).json()
    body = prefs["payload"]
    body["activities"]["maths"]["enabled"] = False
    client.put(f"/v1/children/{child['id']}/preferences", headers=alice, json=body)
    r = client.post("/v1/device/sessions", headers=dev_auth(cred),
                    json={"client_session_id": "abcdefgh", "activity_key": "maths"})
    assert r.status_code == 409


def test_latency_samples_and_percentiles(client, alice):
    _child, cred = _setup(client, alice)
    samples = [{"metric": "speech_end_to_first_audio", "value_ms": v,
                "conditions": "simulator"} for v in range(100, 1100, 10)]  # fmt: skip
    assert client.post("/v1/device/telemetry/latency", headers=dev_auth(cred),
                       json={"samples": samples}).status_code == 202
    stats = {s["metric"]: s for s in client.get("/dev/latency").json()}
    s = stats["speech_end_to_first_audio"]
    assert s["count"] == 100 and 590 <= s["p50_ms"] <= 600 and 1030 <= s["p95_ms"] <= 1050


def test_logging_redacts_secrets():
    from app.logging import redact_processor

    out = redact_processor(None, "info", {"event": "x", "password": "p", "claim_token": "t",
                                          "nested": {"wifi_psk": "k", "ok": 1}, "path": "/v1"})
    assert out["password"] == out["claim_token"] == "[redacted]"
    assert out["nested"] == {"wifi_psk": "[redacted]", "ok": 1}
    assert out["path"] == "/v1"
