"""Small HTTP API around the session-16 calculator.

The calculator functions in calculator.py come from the instructor's
10-final-cicd-pipeline example. This file wraps them in a Flask app so the
pipeline has something it can put in a container, deploy to Kubernetes and
smoke-test with curl.
"""

import os

from flask import Flask, jsonify, request

from app.calculator import add, divide, multiply, subtract

APP_NAME = "session16-calculator"
APP_VERSION = "1.0.0"

OPERATIONS = {
    "add": add,
    "subtract": subtract,
    "multiply": multiply,
    "divide": divide,
}

app = Flask(__name__)


@app.get("/")
def index():
    return jsonify(
        app=APP_NAME,
        version=APP_VERSION,
        # GIT_SHA is baked into the image by the Dockerfile (build arg), so the
        # deployed pod can tell us exactly which commit it was built from.
        commit=os.environ.get("GIT_SHA", "unknown"),
        operations=sorted(OPERATIONS),
    )


@app.get("/health")
def health():
    return jsonify(status="ok")


@app.get("/api/<operation>")
def calculate(operation):
    func = OPERATIONS.get(operation)
    if func is None:
        return jsonify(error=f"unknown operation '{operation}'", valid=sorted(OPERATIONS)), 404

    try:
        a = float(request.args["a"])
        b = float(request.args["b"])
    except KeyError:
        return jsonify(error="query parameters 'a' and 'b' are required"), 400
    except ValueError:
        return jsonify(error="'a' and 'b' must be numbers"), 400

    try:
        result = func(a, b)
    except ValueError as exc:  # divide by zero
        return jsonify(error=str(exc)), 400

    return jsonify(operation=operation, a=a, b=b, result=result)
