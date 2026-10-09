async function runCacheDemo() {
  const resultDiv = document.getElementById('cacheResult');
  resultDiv.textContent = "Fetching...";
  const start = performance.now();
  const res = await fetch('/api/cache-demo');
  const data = await res.json();
  const total = ((performance.now() - start) / 1000).toFixed(2);

  resultDiv.innerHTML = `Source: <b>${data.source}</b> | Data: ${data.data} | Total time: ${total}s`;
}

async function incrementCounter() {
  const res = await fetch('/api/counter/increment', { method: 'POST' });
  const data = await res.json();
  document.getElementById('counterValue').textContent = data.count;
}

async function loadCounter() {
  const res = await fetch('/api/counter');
  const data = await res.json();
  document.getElementById('counterValue').textContent = data.count;
}

async function setKV() {
  const key = document.getElementById('kvKey').value;
  const value = document.getElementById('kvValue').value;
  const ttl = document.getElementById('kvTtl').value;

  const res = await fetch('/api/kv/set', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ key, value, ttl })
  });
  const data = await res.json();
  document.getElementById('kvResult').textContent = data.message;
}

async function getKV() {
  const key = document.getElementById('kvKey').value;
  const res = await fetch('/api/kv/get/' + key);
  const data = await res.json();

  const resultDiv = document.getElementById('kvResult');
  if (data.found) {
    resultDiv.textContent = `Value: ${data.value} | Expires in: ${data.ttl_remaining}s`;
  } else {
    resultDiv.textContent = "Key not found (maybe expired?)";
  }
}

window.onload = loadCounter;
