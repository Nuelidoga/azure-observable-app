"""Task tracker API: the payload for the DevOps pipeline."""
import os
import signal
import uuid

if os.getenv("APPLICATIONINSIGHTS_CONNECTION_STRING"):
    from azure.monitor.opentelemetry import configure_azure_monitor

    configure_azure_monitor()

from flask import Flask, jsonify, request  # noqa: E402
from werkzeug.utils import secure_filename  # noqa: E402

import db  # noqa: E402
import storage  # noqa: E402

app = Flask(__name__)
APP_VERSION = os.getenv("APP_VERSION", "dev")
CHAOS = os.getenv("ENABLE_CHAOS", "false").lower() == "true"
_db_ready = False


def ensure_db():
    global _db_ready
    if not _db_ready:
        db.init()
        _db_ready = True


@app.get("/health")
def health():
    """Liveness: never touches dependencies."""
    return jsonify(status="ok", version=APP_VERSION)


@app.get("/ready")
def ready():
    """Readiness: checks the database."""
    try:
        ensure_db()
        db.ping()
        return jsonify(status="ready", version=APP_VERSION)
    except Exception as exc:  # noqa: BLE001
        app.logger.exception("readiness check failed")
        return jsonify(status="not ready", error=type(exc).__name__), 503


@app.get("/tasks")
def get_tasks():
    ensure_db()
    return jsonify(db.list_tasks())


@app.post("/tasks")
def create_task():
    ensure_db()
    body = request.get_json(silent=True) or {}
    title = str(body.get("title", "")).strip()
    if not title or len(title) > 200:
        return jsonify(error="title is required (max 200 chars)"), 400
    return jsonify(id=db.add_task(title), title=title), 201


@app.post("/uploads")
def upload_file():
    file = request.files.get("file")
    if file is None or not file.filename:
        return jsonify(error="multipart field 'file' is required"), 400
    name = f"{uuid.uuid4().hex[:8]}-{secure_filename(file.filename)}"
    storage.upload(name, file.read())
    return jsonify(blob=name), 201


@app.get("/uploads")
def list_uploads():
    return jsonify(storage.list_names())


# ---- chaos endpoints: used only to demonstrate alerts (ENABLE_CHAOS=true) ----
@app.get("/chaos/error")
def chaos_error():
    if not CHAOS:
        return jsonify(error="chaos disabled"), 404
    return jsonify(error="injected failure"), 500


@app.get("/chaos/crash")
def chaos_crash():
    if not CHAOS:
        return jsonify(error="chaos disabled"), 404
    os.kill(os.getppid(), signal.SIGKILL)  # kill the gunicorn master -> container restart
    return "", 204
