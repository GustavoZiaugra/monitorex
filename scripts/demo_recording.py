#!/usr/bin/env python3
"""Monitorex Demo — Polished terminal recording with Rich."""

import json
import subprocess
import time
import sys
import os

from rich.console import Console
from rich.table import Table
from rich.panel import Panel
from rich.syntax import Syntax
from rich.rule import Rule
from rich import box
from rich.text import Text
from rich.align import Align

console = Console()

PROJECT_DIR = "/home/zig/projects/monitorex"
HOME_DIR = os.path.expanduser('~')
ELIXIR_PATH = f"{HOME_DIR}/.asdf/installs/elixir/1.19.5-otp-28/bin:{HOME_DIR}/.asdf/installs/erlang/28.5/bin"


def step(title, delay=1.0):
    console.print()
    console.print(Rule(f"[bold cyan]{title}[/bold cyan]", style="blue"))
    time.sleep(delay)


def run_cmd(cmd, cwd=PROJECT_DIR):
    env = os.environ.copy()
    env["PATH"] = f"{ELIXIR_PATH}:{env.get('PATH', '')}"
    result = subprocess.run(cmd, shell=True, cwd=cwd, capture_output=True, text=True, env=env)
    return result.stdout + result.stderr


# ==============================
# DEMO START
# ==============================

console.clear()

# ——— 1. Big Header ———
header = Panel(
    Align.center(
        Text("Monitorex", style="bold cyan", no_wrap=True) + "\n" +
        Text("Real-time HTTP Telemetry Dashboard for Elixir/Phoenix", style="white"),
    ),
    border_style="bright_blue",
    box=box.DOUBLE_EDGE,
    padding=(1, 2),
)
console.print(header)
time.sleep(1.5)

# Features
t = Table(box=box.ROUNDED, border_style="dim", show_header=False, pad_edge=False)
t.add_column(style="bold cyan", width=20)
t.add_column(style="white", width=45)
t.add_row("📡 Outbound", "Tesla, Finch, Req — hosts, endpoints, latency")
t.add_row("📥 Inbound", "Phoenix routes, consumers, status codes")
t.add_row("🕐 Timeline", "Split-pane event inspector with detail viewer")
t.add_row("⚡ Live Updates", "LiveView auto-refresh every 2s")
t.add_row("📊 Prometheus", "GET /monitorex/metrics for scraping")
t.add_row("🔔 Alerts", "Configurable webhooks (error_rate, host_down, high_latency)")
t.add_row("🌙 Dark Theme", "Polished design system with SVG icons")
t.add_row("📦 No DB", "All data in ETS — zero database setup")
console.print(Panel(t, title="[bold]Features", border_style="cyan"))
time.sleep(2)

# ——— 2. Quick Start ———
step("📖 Quick Start")
show = Panel(
    "Add to [bold]mix.exs[/bold]:\n\n"
    "  [green]{:monitorex, \"~> 0.5.0\"}[/green]\n\n"
    "Configure [bold]:sources[/bold]:\n\n"
    "  [yellow]config :monitorex, :sources, [:tesla, :finch, :req, :phoenix][/yellow]\n\n"
    "Mount in router:\n\n"
    '  [cyan]scope "/monitoring" do[/cyan]\n'
    "    [cyan]pipe_through :browser[/cyan]\n"
    "    [cyan]http_dashboard [] [dim]# 8 pages, health, metrics[/dim][/cyan]\n"
    "  [cyan]end[/cyan]",
    border_style="green"
)
console.print(show)
time.sleep(2)

# ——— 3. Start Demo Server ———
step("🚀 Starting Demo Server")
console.print("[dim]> mix run scripts/demo.exs[/dim]\n")
time.sleep(1)

server_proc = subprocess.Popen(
    ["mix", "run", "scripts/demo.exs"],
    cwd=PROJECT_DIR,
    stdout=subprocess.PIPE,
    stderr=subprocess.STDOUT,
    text=True,
    env={**os.environ, "PATH": f"{ELIXIR_PATH}:{os.environ.get('PATH', '')}"}
)
time.sleep(4)
# Drain startup output
while server_proc.stdout and server_proc.stdout.readable():
    line = server_proc.stdout.readline()
    if "http://localhost:4000" in line:
        break

console.print("[green]✓[/green] Server running at [bold]http://localhost:4000[/bold]")
time.sleep(1)

# ——— 4. Health Check ———
step("💚 Health Endpoint — GET /monitorex/health")
health = run_cmd("curl -s http://localhost:4000/monitorex/health")
try:
    data = json.loads(health)
    console.print(Syntax(json.dumps(data, indent=2), "json", theme="monokai"))
except:
    console.print(health)
time.sleep(2)

# ——— 5. Dashboard Pages Table ———
step("🖥️  Dashboard Pages (8 LiveView pages)")
t = Table(box=box.ROUNDED, show_header=True, header_style="bold cyan")
t.add_column("Page", style="white")
t.add_column("URL", style="dim")
t.add_column("Description", style="green")
t.add_row("Outbound Overview", "/", "Summary cards + host table")
t.add_row("Outbound Recent", "/outbound_recent", "Live feed with status filter")
t.add_row("Host Detail", "/host/:host", "Per-endpoint breakdown + recent")
t.add_row("Inbound Overview", "/inbound", "Route table + consumer summary")
t.add_row("Inbound Consumers", "/inbound_consumers", "Per-consumer stats")
t.add_row("Inbound Recent", "/inbound_recent", "Live feed with filters")
t.add_row("Timeline Inspector", "/timeline", "Split-pane event + detail viewer")
t.add_row("Route Detail", "/route/:key", "Consumer breakdown + recent")
console.print(t)
time.sleep(2.5)

# ——— 6. Config ———
step("⚙️  Configuration Highlights")
t = Table(box=box.ROUNDED, show_header=True, header_style="bold cyan")
t.add_column("Option", style="white")
t.add_column("Default", style="yellow")
t.add_column("Description", style="dim")
t.add_row(":sources", "[]", "HTTP clients to monitor")
t.add_row(":max_endpoints", "2_000", "Max aggregate entries")
t.add_row(":max_recent", "500", "Ring buffer size per direction")
t.add_row(":endpoint_ttl", "1 hour", "Stale entry TTL")
t.add_row(":redacted_headers", "auth,cookie,...", "Header redaction")
t.add_row(":store_request_body", "false", "Capture request bodies")
t.add_row(":store_response_body", "false", "Capture response bodies")
t.add_row(":max_body_bytes", "10_000", "Body truncation")
console.print(t)
time.sleep(2.5)

# ——— 7. Memory ———
step("🧠 Zero-DB — All in ETS")
console.print(Panel(
    "[bold cyan]Monitorex.memory_usage()[/bold cyan]\n\n"
    "All data lives in Erlang ETS tables:\n"
    "  • Host aggregates, endpoint stats, route tables\n"
    "  • Recent event ring buffers (ordered_set)\n"
    "  • Duration samples (bag tables)\n\n"
    "[dim]No Postgres, no Redis, no disk writes.[/dim]\n"
    "[dim]Just BEAM magic. ✨[/dim]",
    border_style="yellow"
))
time.sleep(2)

# ——— 8. Outro ———
step("✅ Demo Complete")

# Kill server
server_proc.terminate()
try:
    server_proc.wait(timeout=5)
except:
    server_proc.kill()

console.print()
outro = Panel(
    Align.center(
        "[bold green]Monitorex[/bold green]\n\n"
        "[dim]https://github.com/GustavoZiaugra/monitorex[/dim]\n"
        "[dim]https://hex.pm/packages/monitorex[/dim]\n\n"
        "[cyan]mix.exs:  {:monitorex, \"~> 0.5.0\"}[/cyan]"
    ),
    border_style="bright_green",
    box=box.DOUBLE_EDGE,
    padding=(1, 2),
)
console.print(outro)
time.sleep(1)
console.print("\n[dim]✨ Thanks for watching![/dim]")
time.sleep(1)
