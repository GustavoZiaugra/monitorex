#!/usr/bin/env bash
export FORCE_COLOR=1
export TERM=xterm-256color
export CLICOLOR_FORCE=1
export PATH="$HOME/.asdf/installs/elixir/1.19.5-otp-28/bin:$HOME/.asdf/installs/erlang/28.5/bin:$PATH"
cd /home/zig/projects/monitorex
python3 scripts/demo_recording.py
