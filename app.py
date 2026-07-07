from flask import Flask, request, jsonify, render_template_string
import os
import uuid
import subprocess

app = Flask(__name__)

# Reject anything absurdly large so a bad upload can't wedge the Pi.
app.config["MAX_CONTENT_LENGTH"] = 60 * 1024 * 1024  # 60 MB

# Where dropped photos land. install.sh sets HOTFOLDER_ROOT in the systemd unit
# so this works no matter what username the Pi was flashed with. The default is
# only a fallback for running by hand.
HOTFOLDER_ROOT = os.environ.get(
    "HOTFOLDER_ROOT",
    os.path.join(os.path.expanduser("~"), "print-hotfolder"),
)

HOTFOLDERS = {
    "4x6": os.path.join(HOTFOLDER_ROOT, "4x6"),
    "4x4": os.path.join(HOTFOLDER_ROOT, "4x4"),
    "4x6_2stripes": os.path.join(HOTFOLDER_ROOT, "4x6_2stripes"),
    "4x6_3stripes": os.path.join(HOTFOLDER_ROOT, "4x6_3stripes"),
}

QUEUES = [
    "Dai_Nippon_Printing_DP-QW410_4x6",
    "Dai_Nippon_Printing_DP-QW410_4x4",
    "Dai_Nippon_Printing_DP-QW410_4x6_2_Stripes",
    "Dai_Nippon_Printing_DP-QW410_4x6_3_Stripes",
]

ALLOWED_EXTENSIONS = {"jpg", "jpeg", "png"}

def allowed_file(filename):
    return "." in filename and filename.rsplit(".", 1)[1].lower() in ALLOWED_EXTENSIONS

HTML = r"""<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>KRUU Print Station</title>
<link rel="preconnect" href="https://fonts.googleapis.com">
<link href="https://fonts.googleapis.com/css2?family=Bebas+Neue&family=DM+Mono:wght@400;500&family=DM+Sans:wght@300;400;500&display=swap" rel="stylesheet">
<style>
  *, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; }
  :root {
    --bg: #ffffff;
    --surface: #f8f8f8;
    --surface2: #f0f0f0;
    --border: #e0e0e0;
    --border-dark: #999;
    --text: #0a0a0a;
    --muted: #888;
  }
  body {
    background: var(--bg);
    color: var(--text);
    font-family: 'DM Sans', sans-serif;
    min-height: 100vh;
    display: flex;
    flex-direction: column;
    align-items: center;
    padding: 48px 20px;
  }
  header {
    width: 100%;
    max-width: 680px;
    margin-bottom: 48px;
    display: flex;
    align-items: baseline;
    justify-content: space-between;
    border-bottom: 2px solid var(--text);
    padding-bottom: 20px;
  }
  .logo {
    font-family: 'Bebas Neue', sans-serif;
    font-size: 48px;
    letter-spacing: 6px;
    color: var(--text);
    line-height: 1;
  }
  .logo-sub {
    font-family: 'DM Mono', monospace;
    font-size: 10px;
    color: var(--muted);
    letter-spacing: 4px;
    text-transform: uppercase;
  }
  .card {
    width: 100%;
    max-width: 680px;
    border: 1px solid var(--border);
    padding: 28px;
    margin-bottom: 12px;
  }
  .section-label {
    font-family: 'DM Mono', monospace;
    font-size: 10px;
    letter-spacing: 3px;
    text-transform: uppercase;
    color: var(--muted);
    margin-bottom: 16px;
  }
  .size-grid {
    display: grid;
    grid-template-columns: 1fr 1fr;
    gap: 8px;
  }
  .size-btn {
    background: var(--bg);
    border: 1px solid var(--border);
    padding: 16px 20px;
    cursor: pointer;
    transition: all 0.1s;
    text-align: left;
    color: var(--text);
  }
  .size-btn:hover { border-color: var(--text); background: var(--surface); }
  .size-btn.active { border-color: var(--text); background: var(--text); color: white; }
  .size-name {
    font-family: 'Bebas Neue', sans-serif;
    font-size: 24px;
    letter-spacing: 1px;
    line-height: 1;
    margin-bottom: 4px;
  }
  .size-desc {
    font-size: 10px;
    opacity: 0.6;
    font-family: 'DM Mono', monospace;
    letter-spacing: 1px;
  }
  .drop-zone {
    border: 1px dashed var(--border-dark);
    padding: 52px 32px;
    text-align: center;
    cursor: pointer;
    transition: all 0.15s;
    background: var(--surface);
  }
  .drop-zone:hover, .drop-zone.dragover {
    border-color: var(--text);
    border-style: solid;
    background: var(--surface2);
  }
  .drop-icon { font-size: 28px; margin-bottom: 14px; opacity: 0.25; }
  .drop-title {
    font-family: 'Bebas Neue', sans-serif;
    font-size: 22px;
    letter-spacing: 3px;
    margin-bottom: 6px;
  }
  .drop-sub {
    font-size: 11px;
    color: var(--muted);
    font-family: 'DM Mono', monospace;
    letter-spacing: 1px;
  }
  #file-input { display: none; }
  .preview-grid {
    display: grid;
    grid-template-columns: repeat(auto-fill, minmax(90px, 1fr));
    gap: 6px;
    margin-top: 14px;
  }
  .preview-item {
    position: relative;
    aspect-ratio: 1;
    overflow: hidden;
    border: 1px solid var(--border);
  }
  .preview-item img { width: 100%; height: 100%; object-fit: cover; }
  .preview-item .remove {
    position: absolute;
    top: 3px; right: 3px;
    background: rgba(0,0,0,0.7);
    color: white;
    border: none;
    width: 18px; height: 18px;
    cursor: pointer;
    font-size: 9px;
    display: flex; align-items: center; justify-content: center;
  }
  .print-btn {
    width: 100%;
    max-width: 680px;
    background: var(--text);
    color: white;
    border: none;
    padding: 18px;
    font-family: 'Bebas Neue', sans-serif;
    font-size: 20px;
    letter-spacing: 5px;
    cursor: pointer;
    transition: background 0.1s;
    margin-top: 4px;
  }
  .print-btn:hover { background: #333; }
  .print-btn:disabled { background: var(--border); color: var(--muted); cursor: not-allowed; }
  .reset-btn {
    width: 100%;
    max-width: 680px;
    background: var(--bg);
    color: var(--text);
    border: 1px solid var(--border);
    padding: 14px;
    font-family: 'DM Mono', monospace;
    font-size: 11px;
    letter-spacing: 3px;
    cursor: pointer;
    transition: all 0.1s;
    margin-top: 8px;
    text-transform: uppercase;
  }
  .reset-btn:hover { border-color: var(--text); background: var(--surface); }
  .reset-btn:disabled { opacity: 0.4; cursor: not-allowed; }
  .status-bar {
    width: 100%;
    max-width: 680px;
    display: flex;
    align-items: center;
    gap: 8px;
    padding: 14px 0 0;
    font-family: 'DM Mono', monospace;
    font-size: 10px;
    color: var(--muted);
    letter-spacing: 1px;
  }
  .status-dot {
    width: 5px; height: 5px;
    border-radius: 50%;
    background: #333;
    animation: pulse 2.5s infinite;
  }
  @keyframes pulse { 0%, 100% { opacity: 1; } 50% { opacity: 0.2; } }
  .toast {
    position: fixed;
    bottom: 28px;
    left: 50%;
    transform: translateX(-50%) translateY(80px);
    background: var(--text);
    color: white;
    padding: 12px 24px;
    font-family: 'DM Mono', monospace;
    font-size: 11px;
    letter-spacing: 2px;
    transition: transform 0.25s cubic-bezier(0.34, 1.56, 0.64, 1);
    z-index: 100;
    white-space: nowrap;
    text-transform: uppercase;
  }
  .toast.show { transform: translateX(-50%) translateY(0); }
  .toast.error { background: #c00; }
</style>
</head>
<body>
<header>
  <div class="logo">KRUU</div>
  <div class="logo-sub">Print Station</div>
</header>

<div class="card">
  <div class="section-label">01 &mdash; Print Size</div>
  <div class="size-grid">
    <button class="size-btn active" data-size="4x6" onclick="selectSize(this)">
      <div class="size-name">4 &times; 6</div>
      <div class="size-desc">Standard photo</div>
    </button>
    <button class="size-btn" data-size="4x4" onclick="selectSize(this)">
      <div class="size-name">4 &times; 4</div>
      <div class="size-desc">Square format</div>
    </button>
    <button class="size-btn" data-size="4x6_2stripes" onclick="selectSize(this)">
      <div class="size-name">2 Strips</div>
      <div class="size-desc">Two 4&times;2 strips</div>
    </button>
    <button class="size-btn" data-size="4x6_3stripes" onclick="selectSize(this)">
      <div class="size-name">3 Strips</div>
      <div class="size-desc">Three 4&times;2 strips</div>
    </button>
  </div>
</div>

<div class="card">
  <div class="section-label">02 &mdash; Photos</div>
  <div class="drop-zone" id="drop-zone" onclick="document.getElementById('file-input').click()">
    <div class="drop-icon">&#8595;</div>
    <div class="drop-title">Drop Photos Here</div>
    <div class="drop-sub">or click to browse &mdash; JPG &amp; PNG accepted</div>
  </div>
  <input type="file" id="file-input" accept=".jpg,.jpeg,.png" multiple>
  <div class="preview-grid" id="preview-grid"></div>
</div>

<button class="print-btn" id="print-btn" disabled onclick="printFiles()">
  Send to Printer
</button>

<button class="reset-btn" id="reset-btn" onclick="resetPrinter()">
  &#8635; Clear Queue &amp; Reset Printer
</button>

<div class="status-bar">
  <div class="status-dot"></div>
  <span>Print server online &mdash; <span id="host">&mdash;</span></span>
</div>

<div class="toast" id="toast"></div>

<script>
const RESET_LABEL = '↻ Clear Queue & Reset Printer';
let selectedSize = '4x6';
let files = [];

document.getElementById('host').textContent = location.host;

function selectSize(btn) {
  document.querySelectorAll('.size-btn').forEach(b => b.classList.remove('active'));
  btn.classList.add('active');
  selectedSize = btn.dataset.size;
}

function showToast(msg, type) {
  const t = document.getElementById('toast');
  t.textContent = msg;
  t.className = 'toast ' + (type || '') + ' show';
  setTimeout(() => t.classList.remove('show'), 3500);
}

function updatePrintBtn() {
  document.getElementById('print-btn').disabled = files.filter(Boolean).length === 0;
}

function addFiles(newFiles) {
  Array.from(newFiles).forEach(file => {
    if (!file.type.match(/image\/(jpeg|png)/)) return;
    const idx = files.push(file) - 1;
    const reader = new FileReader();
    reader.onload = e => {
      const grid = document.getElementById('preview-grid');
      const item = document.createElement('div');
      item.className = 'preview-item';
      item.dataset.idx = idx;
      item.innerHTML = '<img src="' + e.target.result + '"><button class="remove" onclick="removeFile(this.parentElement)">&#10005;</button>';
      grid.appendChild(item);
    };
    reader.readAsDataURL(file);
  });
  updatePrintBtn();
}

function removeFile(el) {
  const idx = parseInt(el.dataset.idx);
  files[idx] = null;
  el.remove();
  updatePrintBtn();
}

document.getElementById('file-input').addEventListener('change', e => addFiles(e.target.files));

const dz = document.getElementById('drop-zone');
dz.addEventListener('dragover', e => { e.preventDefault(); dz.classList.add('dragover'); });
dz.addEventListener('dragleave', () => dz.classList.remove('dragover'));
dz.addEventListener('drop', e => { e.preventDefault(); dz.classList.remove('dragover'); addFiles(e.dataTransfer.files); });

async function printFiles() {
  const validFiles = files.filter(Boolean);
  if (!validFiles.length) return;
  const btn = document.getElementById('print-btn');
  btn.disabled = true;
  btn.textContent = 'Sending...';
  let sent = 0;
  for (const file of validFiles) {
    const fd = new FormData();
    fd.append('file', file);
    fd.append('size', selectedSize);
    try {
      const res = await fetch('/print', { method: 'POST', body: fd });
      const data = await res.json();
      if (data.success) sent++;
    } catch(e) {}
  }
  files = [];
  document.getElementById('preview-grid').innerHTML = '';
  btn.textContent = 'Send to Printer';
  updatePrintBtn();
  if (sent === validFiles.length) {
    showToast(sent + ' photo' + (sent > 1 ? 's' : '') + ' sent to printer');
  } else if (sent > 0) {
    showToast(sent + ' of ' + validFiles.length + ' sent - check printer', 'error');
    btn.disabled = false;
  } else {
    showToast('Error - check printer', 'error');
    btn.disabled = false;
  }
}

async function resetPrinter() {
  const btn = document.getElementById('reset-btn');
  btn.disabled = true;
  btn.textContent = 'Resetting...';
  try {
    const res = await fetch('/reset', { method: 'POST' });
    const data = await res.json();
    if (data.success) {
      showToast('Queue cleared - printer ready');
    } else {
      showToast('Reset failed - check printer', 'error');
    }
  } catch(e) {
    showToast('Reset failed', 'error');
  }
  btn.disabled = false;
  btn.textContent = RESET_LABEL;
}
</script>
</body>
</html>"""

@app.route("/")
def index():
    return render_template_string(HTML)

@app.route("/health")
def health():
    return jsonify({"status": "ok"})

@app.route("/print", methods=["POST"])
def print_file():
    if "file" not in request.files:
        return jsonify({"success": False, "error": "No file"}), 400
    file = request.files["file"]
    size = request.form.get("size", "4x6")
    if not file or not file.filename or not allowed_file(file.filename):
        return jsonify({"success": False, "error": "Invalid file"}), 400
    if size not in HOTFOLDERS:
        return jsonify({"success": False, "error": "Invalid size"}), 400
    folder = HOTFOLDERS[size]
    try:
        os.makedirs(folder, exist_ok=True)
        ext = file.filename.rsplit(".", 1)[1].lower()
        filename = f"{uuid.uuid4().hex}.{ext}"
        filepath = os.path.join(folder, filename)
        file.save(filepath)
        os.chmod(filepath, 0o664)
    except OSError as e:
        return jsonify({"success": False, "error": str(e)}), 500
    return jsonify({"success": True})

@app.errorhandler(413)
def too_large(e):
    return jsonify({"success": False, "error": "File too large"}), 413

@app.route("/reset", methods=["POST"])
def reset_printer():
    try:
        results = []
        # Cancel all jobs (jobs are submitted as this user, so no sudo needed).
        results.append(subprocess.run(["cancel", "-a"], capture_output=True).returncode)
        # Re-enable every queue in case one got disabled (ribbon out, jam, etc).
        for queue in QUEUES:
            results.append(
                subprocess.run(["sudo", "cupsenable", queue], capture_output=True).returncode
            )
        # Restart CUPS to clear any wedged USB state.
        results.append(
            subprocess.run(["sudo", "systemctl", "restart", "cups"], capture_output=True).returncode
        )
        ok = all(rc == 0 for rc in results)
        return jsonify({"success": ok})
    except Exception as e:
        return jsonify({"success": False, "error": str(e)}), 500

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080, debug=False, threaded=True)
