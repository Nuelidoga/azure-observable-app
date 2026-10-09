import main


def test_health_ok():
    r = main.app.test_client().get("/health")
    assert r.status_code == 200
    assert r.get_json()["status"] == "ok"


def test_chaos_disabled_by_default():
    assert main.app.test_client().get("/chaos/error").status_code == 404


def test_task_requires_title(monkeypatch):
    monkeypatch.setattr(main, "ensure_db", lambda: None)
    r = main.app.test_client().post("/tasks", json={"title": "  "})
    assert r.status_code == 400
