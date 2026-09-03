# Minimal Flask web app that serves a Hello World HTML page.
from flask import Flask
import sys

app = Flask(__name__)

@app.route("/")
def hello():
    return f"""<!DOCTYPE html>
<html lang="en">
  <head><meta charset="utf-8"><title>Hello World - Python</title></head>
  <body>
    <h1>Hello World</h1>
    <p>Served by Python {sys.version.split()[0]} + Flask inside a Docker container.</p>
  </body>
</html>"""

if __name__ == "__main__":
    # 0.0.0.0 so the app is reachable from outside the container.
    # Port 5000 inside the container; on macOS it is remapped to 5001 on the host
    # because AirPlay Receiver already occupies host port 5000.
    app.run(host="0.0.0.0", port=5000)
