#!/usr/bin/env bash
# Monitorex Demo Video Recorder v2 — with real interactions
set -e

PROJECT_DIR="/home/zig/projects/monitorex"
DEMO_DIR="$PROJECT_DIR/demo"
OUTPUT="$DEMO_DIR/monitorex-demo-v2.mp4"
LOG="$DEMO_DIR/recording-v2.log"
XVFB_DISPLAY=":99"
ELIXIR_PATH="$HOME/.asdf/installs/elixir/1.19.5-otp-28/bin:$HOME/.asdf/installs/erlang/28.5/bin"
export PATH="$ELIXIR_PATH:$PATH"

mkdir -p "$DEMO_DIR"

echo "=== Monitorex Demo Recording v2 — Interactive ===" | tee "$LOG"
echo "" | tee -a "$LOG"

# Cleanup
pkill -f "mix run scripts/demo.exs" 2>/dev/null || true
pkill -f "Xvfb" 2>/dev/null || true
sleep 1

# Start Xvfb
Xvfb "$XVFB_DISPLAY" -screen 0 1440x900x24 &
XVFB_PID=$!
sleep 1
export DISPLAY="$XVFB_DISPLAY"

# Start server
cd "$PROJECT_DIR"
mix compile 2>> "$LOG" && mix run scripts/demo.exs &
SERVER_PID=$!
sleep 5
if ! curl -s http://localhost:4000/monitorex/health > /dev/null 2>&1; then
  echo "ERROR: Server failed to start" | tee -a "$LOG"
  kill $SERVER_PID $XVFB_PID 2>/dev/null; exit 1
fi
echo "  ✓ Server running" | tee -a "$LOG"

# Start ffmpeg
ffmpeg -f x11grab -video_size 1440x900 -framerate 15 \
  -draw_mouse 1 -i "$XVFB_DISPLAY" \
  -c:v libx264 -preset ultrafast -crf 28 \
  -pix_fmt yuv420p -y "$OUTPUT" \
  -loglevel warning &
FFMPEG_PID=$!
sleep 1

echo "[Recording] Navigating with interactions..." | tee -a "$LOG"

node -e '
const { chromium } = require("/home/zig/.local/lib/python3.12/site-packages/playwright/driver/package/index.js");

const sleep = (ms) => new Promise(r => setTimeout(r, ms));
const BASE = "http://localhost:4000";

(async () => {
  const browser = await chromium.launch({
    headless: false,
    args: ["--no-sandbox", "--disable-setuid-sandbox", "--disable-gpu"]
  });
  const page = await browser.newPage({ viewport: { width: 1440, height: 900 } });

  // ── 1. OUTBOUND OVERVIEW ──
  console.log("→ Outbound Overview");
  await page.goto(BASE + "/", { waitUntil: "networkidle", timeout: 20000 }).catch(() => {});
  await sleep(3000);

  // ── 2. OUTBOUND RECENT via sidebar click ──
  console.log("→ Outbound Recent (sidebar click)");
  // Click the "Outbound Recent" link in sidebar
  const recentLink = await page.$("nav a[href=\"/outbound_recent\"]");
  if (recentLink) {
    await recentLink.hover();
    await sleep(500);
    await recentLink.click();
  } else {
    await page.goto(BASE + "/outbound_recent", { waitUntil: "networkidle" });
  }
  await sleep(3000);

  // Click on a status filter chip (e.g., "5xx" to filter errors)
  console.log("  → Click 5xx filter");
  const filter5xx = await page.$("text=5xx");
  if (filter5xx) { await filter5xx.click(); await sleep(2000); }
  // Click "All" to reset
  const filterAll = await page.$("text=All");
  if (filterAll) { await filterAll.click(); await sleep(1500); }
  await sleep(1000);

  // ── 3. TIMELINE via sidebar ──
  console.log("→ Timeline Inspector (sidebar click)");
  const timelineLink = await page.$("nav a[href=\"/timeline\"]");
  if (timelineLink) {
    await timelineLink.hover();
    await sleep(500);
    await timelineLink.click();
  } else {
    await page.goto(BASE + "/timeline", { waitUntil: "networkidle" });
  }
  await sleep(4000);

  // Click on a timeline event to see detail
  console.log("  → Click first event in timeline");
  const firstEvent = await page.$(".timeline-event-item, .event-item, .recent-item, table tbody tr");
  if (firstEvent) {
    await firstEvent.hover();
    await sleep(500);
    await firstEvent.click();
    await sleep(3000);
  }
  await sleep(1000);

  // ── 4. HOST DETAIL via clicking on api.example.com in the overview ──
  console.log("→ Host Detail (click api.example.com link)");
  await page.goto(BASE + "/", { waitUntil: "networkidle", timeout: 20000 }).catch(() => {});
  await sleep(2000);
  const hostLink = await page.$("a[href*=\"/host/api.example.com\"]");
  if (hostLink) {
    await hostLink.hover();
    await sleep(500);
    await hostLink.click();
  } else {
    await page.goto(BASE + "/host/api.example.com", { waitUntil: "networkidle" });
  }
  await sleep(3000);

  // Scroll down to see more content
  await page.evaluate(() => window.scrollTo(0, 300));
  await sleep(2000);
  // Scroll back up
  await page.evaluate(() => window.scrollTo(0, 0));
  await sleep(1000);

  // ── 5. INBOUND OVERVIEW via sidebar ──
  console.log("→ Inbound Overview");
  const inboundLink = await page.$("nav a[href=\"/inbound\"]");
  if (inboundLink) {
    await inboundLink.hover();
    await sleep(500);
    await inboundLink.click();
  } else {
    await page.goto(BASE + "/inbound", { waitUntil: "networkidle" });
  }
  await sleep(3000);

  // ── 6. INBOUND CONSUMERS via sidebar ──
  console.log("→ Inbound Consumers");
  const consumersLink = await page.$("nav a[href=\"/inbound_consumers\"]");
  if (consumersLink) {
    await consumersLink.hover();
    await sleep(500);
    await consumersLink.click();
  } else {
    await page.goto(BASE + "/inbound_consumers", { waitUntil: "networkidle" });
  }
  await sleep(3000);

  // Click a column header to sort
  console.log("  → Sort by Error Rate");
  const errorRateHeader = await page.$("text=Error Rate");
  if (errorRateHeader) { await errorRateHeader.click(); await sleep(2000); }
  await sleep(1000);

  // ── 7. INBOUND RECENT via sidebar ──
  console.log("→ Inbound Recent");
  const inboundRecentLink = await page.$("nav a[href=\"/inbound_recent\"]");
  if (inboundRecentLink) {
    await inboundRecentLink.hover();
    await sleep(500);
    await inboundRecentLink.click();
  } else {
    await page.goto(BASE + "/inbound_recent", { waitUntil: "networkidle" });
  }
  await sleep(3000);

  // ── 8. ROUTE DETAIL via clicking on first route ──
  console.log("→ Route Detail");
  await page.goto(BASE + "/inbound", { waitUntil: "networkidle" }).catch(() => {});
  await sleep(2000);
  const routeLink = await page.$("a[href*=\"/route/\"]");
  if (routeLink) {
    await routeLink.hover();
    await sleep(500);
    await routeLink.click();
  } else {
    await page.goto(BASE + "/route/GET%3A%2Fapi%2Fusers", { waitUntil: "networkidle" });
  }
  await sleep(3000);

  // ── 9. Back to MAIN overview, final ──
  console.log("→ Back to Overview");
  await page.goto(BASE + "/", { waitUntil: "networkidle" }).catch(() => {});
  await sleep(3000);

  console.log("✓ All done");
  await browser.close();
})();
' 2>&1 | tee -a "$LOG"

sleep 2

# Stop
kill $FFMPEG_PID 2>/dev/null || true
kill $SERVER_PID 2>/dev/null || true
kill $XVFB_PID 2>/dev/null || true
sleep 1

if [ -f "$OUTPUT" ]; then
  SIZE=$(du -h "$OUTPUT" | cut -f1)
  DUR=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$OUTPUT" 2>/dev/null)
  echo "" | tee -a "$LOG"
  echo "=== Complete ===" | tee -a "$LOG"
  echo "  File: $OUTPUT" | tee -a "$LOG"
  echo "  Size: $SIZE" | tee -a "$LOG"
  echo "  Duration: ${DUR%.*}s" | tee -a "$LOG"
else
  echo "ERROR: No output" | tee -a "$LOG"
  exit 1
fi
