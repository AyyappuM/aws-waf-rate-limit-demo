import socket
import threading

from flask import Flask, jsonify

app = Flask(__name__)

_lock = threading.Lock()
_hit_count = 0


@app.get("/")
def index():
    return jsonify(
        message="Hello from the WAF rate-limiting POC",
        served_by=socket.gethostname(),
    )


@app.get("/health")
def health():
    return jsonify(status="ok")


@app.get("/hit")
def hit():
    global _hit_count
    with _lock:
        _hit_count += 1
        current = _hit_count
    return jsonify(hits=current, served_by=socket.gethostname())


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080)
