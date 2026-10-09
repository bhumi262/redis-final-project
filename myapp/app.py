from flask import Flask, jsonify, request, render_template
import redis
import time

app = Flask(__name__)

r = redis.Redis(host='15.252.106.55', port=6379, decode_responses=True)

@app.route('/')
def home():
    return render_template('index.html')

# ---------- Feature 1: Caching Demo ----------
def slow_data_fetch():
    time.sleep(3)
    return "This is some expensive data fetched from a slow source!"

@app.route('/api/cache-demo')
def cache_demo():
    cached_value = r.get('my_data')
    if cached_value:
        return jsonify({"source": "cache", "data": cached_value, "time_taken_seconds": 0})

    start = time.time()
    fresh_data = slow_data_fetch()
    duration = time.time() - start
    r.setex('my_data', 30, fresh_data)

    return jsonify({
        "source": "database",
        "data": fresh_data,
        "time_taken_seconds": round(duration, 2)
    })

# ---------- Feature 2: Live Visit Counter ----------
@app.route('/api/counter/increment', methods=['POST'])
def increment_counter():
    count = r.incr('visit_counter')
    return jsonify({"count": count})

@app.route('/api/counter')
def get_counter():
    count = r.get('visit_counter') or 0
    return jsonify({"count": int(count)})

# ---------- Feature 3: Key-Value Store with TTL ----------
@app.route('/api/kv/set', methods=['POST'])
def kv_set():
    data = request.get_json()
    key = data.get('key')
    value = data.get('value')
    ttl = int(data.get('ttl', 60))

    r.setex(key, ttl, value)
    return jsonify({"message": f"Key '{key}' saved with {ttl}s expiry"})

@app.route('/api/kv/get/<key>')
def kv_get(key):
    value = r.get(key)
    if value is None:
        return jsonify({"found": False})

    ttl = r.ttl(key)
    return jsonify({"found": True, "value": value, "ttl_remaining": ttl})

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)