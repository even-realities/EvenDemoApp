#!/usr/bin/env python3
"""Simple non-interactive smoke test for FocusAssistant.

This test avoids microphone input and exercises internal logic only.
"""
from tools.focus_assistant import FocusAssistant, DATA_FILE
import os


def run():
    # Ensure we start with a clean log file
    if os.path.exists(DATA_FILE):
        os.remove(DATA_FILE)

    app = FocusAssistant()

    # Connect should fall back to text-only stub
    app.connect()

    # Test suggestion lookup
    reason = "I have distracting thoughts about dinner"
    suggestion = app.suggest_facilitator(reason)
    assert "5-4-3-2-1" in suggestion or suggestion == app.suggest_facilitator(reason)

    # Log a behavior and verify CSV created
    app.log_behavior("Off Task", reason, suggestion)
    assert os.path.exists(DATA_FILE), "Log file not created"

    print("TEST OK — focus assistant logic exercised successfully")


if __name__ == '__main__':
    run()
