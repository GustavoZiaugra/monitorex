#!/usr/bin/env bash
# Monitorex Demo Video Recorder
# Records a browser-based walkthrough of the Monitorex dashboard

set -e

PROJECT_DIR="/home/zig/projects/monitorex"
DEMO_DIR="$PROJECT_DIR/demo"
OUTPUT="$DEMO_DIR/monitorex-demo.mp4"
LOG="$DEMO_DIR/recording.log"
XVFB_DISPLAY=":99"
ELIXIR_PATH="$HOME/.asdf/installs/elixir/1.19.5-otp-28/bin:$HOME/.asdf/installs/erlang/28.5/bin"

export PATH="$ELIXIR_PATH:$PATH"

mkdir -p "$DEMO_DIR"

echo "=== Monitorex Demo Recording ===" | tee "$LOG"
echo "" | tee -a "$LOG"

# ── Step 1: Kill any existing servers ──
echo "[1/6] Cleaning up previous processes..." | tee -a "$LOG"
pkill -f "mix run scripts/demo.exs" 2>/dev/null || true
pkill -f "Xvfb" 2>/dev/null || true
sleep 1

# ── Step 2: Start Xvfb ──
echo "[2/6] Starting virtual display (Xvfb :99)..." | tee -a "$LOG"
Xvfb "$XVFB_DISPLAY" -screen 0 1440x900x24 &
XVFB_PID=$!
sleep 1
export DISPLAY="$XVFB_DISPLAY"

# ── Step 3: Start demo server ──
echo "[3/6] Starting Monitorex demo server..." | tee -a "$LOG"
cd "$PROJECT_DIR"
mix compile 2>> "$LOG" && mix run scripts/demo.exs &
SERVER_PID=$!
sleep 5

# Verify server is up
if ! curl -s http://localhost:4000/monitorex/health > /dev/null 2>&1; then
  echo "ERROR: Server failed to start" | tee -a "$LOG"
  kill $SERVER_PID $XVFB_PID 2>/dev/null
  exit 1
fi
echo "  ✓ Server running at http://localhost:4000" | tee -a "$LOG"

# ── Step 4: Start ffmpeg recording ──
echo "[4/6] Starting ffmpeg screen capture..." | tee -a "$LOG"
ffmpeg -f x11grab -video_size 1440x900 -framerate 15 \
  -draw_mouse 0 -i "$XVFB_DISPLAY" \
  -c:v libx264 -preset ultrafast -crf 28 \
  -pix_fmt yuv420p -y "$OUTPUT" \
  -loglevel warning &
FFMPEG_PID=$!
sleep 1

# ── Step 5: Navigate through dashboard pages ──
echo "[5/6] Navigating through dashboard pages..." | tee -a "$LOG"

node -e '
const { chromium } = require("/home/zig/.local/lib/python3.12/site-packages/playwright/driver/package/index.js");

const sleep = (ms) => new Promise(r => setTimeout(r, ms));

(async () => {
  const browser = await chromium.launch({
    headless: false,
    args: ["--no-sandbox", "--disable-setuid-sandbox", "--disable-gpu"]
  });

  const context = await browser.newContext({
    viewport: { width: 1440, height: 900 },
    deviceScaleFactor: 1
  });

  const page = await context.newPage();

  const pages = [
    { url: "http://localhost:4000/",                wait: 4000, label: "Outbound Overview" },
    { url: "http://localhost:4000/outbound_recent",  wait: 3000, label: "Outbound Recent" },
    { url: "http://localhost:4000/host/api.example.com", wait: 3000, label: "Host Detail" },
    { url: "http://localhost:4000/inbound",          wait: 3000, label: "Inbound Overview" },
    { url: "http://localhost:4000/inbound_consumers", wait: 3000, label: "Inbound Consumers" },
    { url: "http://localhost:4000/inbound_recent",   wait: 3000, label: "Inbound Recent" },
    { url: "http://localhost:4000/timeline",         wait: 4000, label: "Timeline Inspector" },
    { url: "http://localhost:4000/route/GET%3A%2Fapi%2Fusers", wait: 3000, label: "Route Detail" },
    { url: "http://localhost:4000/",                wait: 3000, label: "Back to Overview" },
  ];

  for (const p of pages) {
    console.log("  →", p.label);
    await page.goto(p.url, { waitUntil: "networkidle", timeout: 20000 }).catch(() => {});
    await sleep(p.wait);
  }

  console.log("  ✓ All pages visited");
  await browser.close();
})();
' 2>&1 | tee -a "$LOG"

# Wait for video to finalize
sleep 2

# ── Step 6: Stop recording ──
echo "[6/6] Stopping recording..." | tee -a "$LOG"
kill $FFMPEG_PID 2>/dev/null || true
kill $SERVER_PID 2>/dev/null || true
kill $XVFB_PID 2>/dev/null || true
sleep 1

# Verify output
if [ -f "$OUTPUT" ]; then
  SIZE=$(du -h "$OUTPUT" | cut -f1)
  DURATION=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$OUTPUT" 2>/dev/null)
  echo "" | tee -a "$LOG"
  echo "=== Recording Complete ===" | tee -a "$LOG"
  echo "  File: $OUTPUT" | tee -a "$LOG"
  echo "  Size: $SIZE" | tee -a "$LOG"
  echo "  Duration: ${DURATION%.*}s" | tee -a "$LOG"
else
  echo "ERROR: No output file generated" | tee -a "$LOG"
  exit 1
fi
