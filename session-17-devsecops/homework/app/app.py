"""DevSecOps Dashboard - session 17 homework.

Based on the instructor's session-17-devsecops/demo/app/app.py (same routes,
same UI). Changes I made so it passes the security stages of the pipeline:

* no ``debug=True`` / no bind to 0.0.0.0 in code (Bandit B201, B104) - in the
  container gunicorn serves the app instead of the Flask dev server
* ``secrets.SystemRandom`` instead of the ``random`` module (Bandit B311)
* timezone-aware timestamps (``datetime.utcnow`` is deprecated)
* input validation on ``fail_chance`` and float overflow in ``power``
  (both used to end in a 500 error)
* a few security response headers
"""

import datetime
import os
import platform
import secrets
import sys

from flask import Flask, jsonify, render_template, request

APP_VERSION = "2.1.0"

app = Flask(__name__)

_rng = secrets.SystemRandom()

# --- In-memory storage for demo ---
_request_count = 0
_start_time = datetime.datetime.now(datetime.timezone.utc)


def _now():
    return datetime.datetime.now(datetime.timezone.utc)


def _timestamp():
    return _now().isoformat().replace("+00:00", "Z")


def _increment_requests():
    global _request_count
    _request_count += 1


@app.after_request
def _security_headers(response):
    response.headers["X-Content-Type-Options"] = "nosniff"
    response.headers["X-Frame-Options"] = "DENY"
    response.headers["Referrer-Policy"] = "no-referrer"
    return response


# ─────────────────────────────────────────────────────────
#  Pages
# ─────────────────────────────────────────────────────────

@app.route("/")
def home():
    _increment_requests()
    return render_template("index.html")


# ─────────────────────────────────────────────────────────
#  Health & Status API
# ─────────────────────────────────────────────────────────

@app.route("/health")
def health():
    _increment_requests()
    uptime_seconds = (_now() - _start_time).total_seconds()
    return jsonify({
        "status": "healthy",
        "uptime_seconds": round(uptime_seconds, 2),
        "timestamp": _timestamp(),
    })


@app.route("/api/status")
def status():
    _increment_requests()
    uptime = _now() - _start_time
    hours, remainder = divmod(int(uptime.total_seconds()), 3600)
    minutes, seconds = divmod(remainder, 60)
    return jsonify({
        "app": "DevSecOps Dashboard",
        "version": APP_VERSION,
        # Baked into the image by the Dockerfile so the deployed pod reports
        # the exact commit it was built from.
        "commit": os.environ.get("GIT_SHA", "unknown"),
        "status": "running",
        "python_version": sys.version.split()[0],
        "platform": platform.system(),
        "uptime": f"{hours:02d}h {minutes:02d}m {seconds:02d}s",
        "total_requests": _request_count,
        "timestamp": _timestamp(),
    })


# ─────────────────────────────────────────────────────────
#  Greeting API
# ─────────────────────────────────────────────────────────

@app.route("/api/greet/<name>")
def greet(name):
    _increment_requests()
    greetings = [
        f"Hello, {name}! 👋",
        f"Hey {name}, welcome aboard! 🚀",
        f"Greetings, {name}! You rock! 🌟",
        f"What's up, {name}! Happy coding! 💻",
        f"Hi {name}! May your pipelines always pass! ✅",
    ]
    return jsonify({
        "message": _rng.choice(greetings),
        "name": name,
        "timestamp": _timestamp(),
    })


# ─────────────────────────────────────────────────────────
#  Math API
# ─────────────────────────────────────────────────────────

@app.route("/api/add", methods=["POST"])
def add_numbers():
    _increment_requests()
    data = request.get_json(silent=True)
    if not data:
        return jsonify({"error": "No JSON body provided"}), 400

    number1 = data.get("number1")
    number2 = data.get("number2")

    if number1 is None or number2 is None:
        return jsonify({"error": "Both number1 and number2 are required"}), 400

    try:
        n1, n2 = float(number1), float(number2)
    except (TypeError, ValueError):
        return jsonify({"error": "Values must be numbers"}), 400

    return jsonify({
        "number1": n1,
        "number2": n2,
        "operation": "addition",
        "result": n1 + n2,
    })


_OPERATIONS = {
    "add":      (lambda a, b: a + b, "+"),
    "subtract": (lambda a, b: a - b, "-"),
    "multiply": (lambda a, b: a * b, "×"),
    "divide":   (lambda a, b: a / b, "÷"),
    "power":    (lambda a, b: a ** b, "^"),
    "modulo":   (lambda a, b: a % b, "%"),
}


@app.route("/api/calculate", methods=["POST"])
def calculate():
    """Multi-operation calculator."""
    _increment_requests()
    data = request.get_json(silent=True)
    if not data:
        return jsonify({"error": "No JSON body provided"}), 400

    a = data.get("a")
    b = data.get("b")
    op = data.get("operation", "add")

    if a is None or b is None:
        return jsonify({"error": "Fields 'a' and 'b' are required"}), 400

    try:
        a, b = float(a), float(b)
    except (TypeError, ValueError):
        return jsonify({"error": "Values must be numbers"}), 400

    if op not in _OPERATIONS:
        return jsonify({"error": f"Unknown operation '{op}'. Valid: {list(_OPERATIONS)}"}), 400

    func, symbol = _OPERATIONS[op]
    try:
        result = func(a, b)
    except ZeroDivisionError:
        return jsonify({"error": "Division by zero"}), 400
    except OverflowError:
        return jsonify({"error": "Result is too large"}), 400

    if isinstance(result, complex):  # e.g. (-8) ** 0.5
        return jsonify({"error": "Result is not a real number"}), 400

    return jsonify({
        "a": a, "b": b,
        "operation": op,
        "symbol": symbol,
        "result": round(result, 10),
        "expression": f"{a} {symbol} {b} = {round(result, 10)}",
    })


# ─────────────────────────────────────────────────────────
#  Pipeline Simulator API
# ─────────────────────────────────────────────────────────

PIPELINE_STAGES = [
    {"name": "Code Checkout",      "icon": "📦"},
    {"name": "Unit Tests",         "icon": "🧪"},
    {"name": "SAST",               "icon": "🔍"},
    {"name": "SCA",                "icon": "📚"},
    {"name": "Secret Scan",        "icon": "🔑"},
    {"name": "Build Docker Image", "icon": "🐳"},
    {"name": "Image Scan",         "icon": "🔒"},
    {"name": "Push to Registry",   "icon": "📤"},
    {"name": "Deploy to K8s",      "icon": "☸️"},
]


@app.route("/api/pipeline/run", methods=["POST"])
def run_pipeline():
    """Simulates a CI/CD pipeline run."""
    _increment_requests()
    data = request.get_json(silent=True) or {}
    branch = str(data.get("branch", "main"))[:100]

    try:
        fail_chance = float(data.get("fail_chance", 0.1))
    except (TypeError, ValueError):
        return jsonify({"error": "fail_chance must be a number between 0 and 1"}), 400
    if not 0 <= fail_chance <= 1:
        return jsonify({"error": "fail_chance must be a number between 0 and 1"}), 400

    stages = []
    failed = False
    for stage in PIPELINE_STAGES:
        if failed:
            stage_status = "skipped"
            duration = 0
        elif _rng.random() < fail_chance:
            stage_status = "failed"
            duration = round(_rng.uniform(0.5, 5.0), 2)
            failed = True
        else:
            stage_status = "passed"
            duration = round(_rng.uniform(0.5, 15.0), 2)

        stages.append({
            "name": stage["name"],
            "icon": stage["icon"],
            "status": stage_status,
            "duration_s": duration,
        })

    overall = "failed" if failed else "passed"
    total_time = round(sum(s["duration_s"] for s in stages), 2)
    run_id = f"run-{_rng.randint(1000, 9999)}"

    return jsonify({
        "run_id": run_id,
        "branch": branch,
        "overall_status": overall,
        "total_time_s": total_time,
        "stages": stages,
        "triggered_at": _timestamp(),
    })


# ─────────────────────────────────────────────────────────
#  Error handlers
# ─────────────────────────────────────────────────────────

@app.errorhandler(404)
def not_found(e):
    return jsonify({"error": "Route not found", "code": 404}), 404


@app.errorhandler(500)
def server_error(e):
    return jsonify({"error": "Internal server error", "code": 500}), 500


if __name__ == "__main__":
    # Local development only. The container runs gunicorn (see Dockerfile).
    app.run(host="127.0.0.1", port=5001)
