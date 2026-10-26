
from flask import Flask, jsonify, request, render_template
from redis.sentinel import Sentinel
import time
import os

app = Flask(__name__)

REDIS_PASSWORD = os.environ.get("REDIS_PASSWORD", "")
REDIS_SENTINELS = os.environ.get(
    "REDIS_SENTINELS",
    "127.0.0.1:26379"
)

sentinel_addresses = []

for address in REDIS_SENTINELS.split(","):
    host, port = address.strip().split(":")
    sentinel_addresses.append((host, int(port)))

sentinel_options = {}


sentinel = Sentinel(
    sentinel_addresses,
    socket_timeout=3,
    sentinel_kwargs=sentinel_options
)

r = sentinel.master_for(
    "mymaster",
    password=REDIS_PASSWORD or None,
    decode_responses=True,
    socket_connect_timeout=3,
    socket_timeout=3
)


@app.route("/")
def home():
    return render_template("index.html")


# Feature 1: Caching Demo
def slow_data_fetch():
    time.sleep(3)
    return "This is some expensive data fetched from a slow source!"


@app.route("/api/cache-demo")
def cache_demo():
    cached_value = r.get("my_data")

    if cached_value:
        return jsonify({
            "source": "cache",
            "data": cached_value,
            "time_taken_seconds": 0
        })

    start = time.time()
    fresh_data = slow_data_fetch()
    duration = time.time() - start

    r.setex("my_data", 30, fresh_data)

    return jsonify({
        "source": "database",
        "data": fresh_data,
        "time_taken_seconds": round(duration, 2)
    })


# Feature 2: Live Visit Counter
@app.route("/api/counter/increment", methods=["POST"])
def increment_counter():
    count = r.incr("visit_counter")
    return jsonify({"count": count})


@app.route("/api/counter")
def get_counter():
    count = r.get("visit_counter") or 0
    return jsonify({"count": int(count)})


# Feature 3: Key-Value Store with TTL
@app.route("/api/kv/set", methods=["POST"])
def kv_set():
    data = request.get_json(silent=True) or {}
    key = data.get("key")
    value = data.get("value")
    ttl = int(data.get("ttl", 60))

    if not key or value is None or ttl <= 0:
        return jsonify({
            "error": "Provide a key, value and positive TTL"
        }), 400

    r.setex(key, ttl, value)

    return jsonify({
        "message": f"Key '{key}' saved with {ttl}s expiry"
    })


@app.route("/api/kv/get/<key>")
def kv_get(key):
    value = r.get(key)

    if value is None:
        return jsonify({"found": False})

    ttl = r.ttl(key)

    return jsonify({
        "found": True,
        "value": value,
        "ttl_remaining": ttl
    })


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)
