# Focus Assistant (Prototype)

A prototype companion app to interact with Even Realities G2 glasses via Bluetooth.

Prerequisites

- Python 3.8+ installed
- System PortAudio (Linux: sudo apt install portaudio19-dev)
- Bluetooth enabled and paired with the glasses

Install

```
python -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
```

Run

```
python tools/focus_assistant.py
```

Notes

- Bluetooth: Ensure device is paired and allowed for your user. Use `bluetoothctl` for pairing.
- PortAudio: On Linux, install `portaudio19-dev` before installing `pyaudio` if pip install fails.
- If `even-glasses` isn't available, the script falls back to a console-only stub.

Data

- Logs saved to `task_behavior_log.csv` in the workspace root.
