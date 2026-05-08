# Demo runner: seeds data then starts Phoenix server
# Usage: mix run priv/run_demo.exs

# Ensure ETS tables exist with seed data
Code.require_file("priv/seed.exs", __DIR__)

# Configure LiveView
Application.put_env(:demo, DemoWeb.Endpoint,
  live_view: [signing_salt: "L4kXpQ7vRm2nJ9wB3tG6"],
  render_errors: [view: Monitorex.ErrorView, accepts: ~w(html)]
)

# Start the Phoenix endpoint
DemoWeb.Endpoint.start_link()

IO.puts("""

╔══════════════════════════════════════════╗
║         Monitorex Dashboard             ║
║                                          ║
║   http://localhost:4000                  ║
║   http://localhost:4000/inbound          ║
║   http://localhost:4000/outbound_recent  ║
║   http://localhost:4000/inbound_consumers║
║   http://localhost:4000/inbound_recent   ║
║                                          ║
║   Press Ctrl+C to stop                  ║
╚══════════════════════════════════════════╝
""")

Process.sleep(:infinity)
