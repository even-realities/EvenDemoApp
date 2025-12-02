#!/usr/bin/env python3
"""
Focus Assistant prototype for Even Realities G2 glasses.

This is the full prototype provided by the user, adapted into a runnable
Python module. It attempts to connect to Even G2 glasses via the
even_glasses wrapper and uses the microphone for a short voice-driven
interaction loop.

Note: This is a prototype — tweak for your environment and library API.
"""
import time
import datetime
import pandas as pd
import speech_recognition as sr

try:
    from even_glasses import EvenGlasses
except Exception:
    # Provide a lightweight stub if the even_glasses package is not present.
    class EvenGlasses:
        def connect(self):
            return False

        def send_text(self, text: str):
            print("[GLASSES]", text)

# --- Configuration ---
FACILITATORS = {
    "distracting thoughts": "Try the '5-4-3-2-1' grounding technique.",
    "negative emotion": "Take 3 deep breaths and name the emotion.",
    "random task": "Write it on a sticky note and return to focus.",
    "fatigue": "Stand up and stretch for 60 seconds.",
    "default": "Remember your goal. You can do this."
}

DATA_FILE = "task_behavior_log.csv"


class FocusAssistant:
    def __init__(self):
        self.glasses = EvenGlasses()
        self.recognizer = sr.Recognizer()
        self.is_running = True

    def connect(self):
        print("Scanning for Even G2 glasses...")
        if self.glasses.connect():
            print("Connected to G2 Glasses!")
            self.glasses.send_text("Focus Assistant\nConnected")
        else:
            print("Could not find glasses. Running in text-only mode.")

    def listen_to_voice(self):
        """Listens for a short phrase via microphone."""
        try:
            with sr.Microphone() as source:
                print("Listening...")
                self.recognizer.adjust_for_ambient_noise(source, duration=0.5)
                audio = self.recognizer.listen(source, timeout=5)
                text = self.recognizer.recognize_google(audio).lower()
                return text
        except (sr.UnknownValueError, sr.WaitTimeoutError):
            return None

    def log_behavior(self, status, note, facilitator_used):
        entry = {
            "timestamp": datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
            "status": status,
            "note": note,
            "facilitator": facilitator_used
        }

        df = pd.DataFrame([entry])
        try:
            df.to_csv(DATA_FILE, mode='a', header=not pd.io.common.file_exists(DATA_FILE), index=False)
        except OSError:
            df.to_csv(DATA_FILE, mode='a', header=True, index=False)

        print(f"LOGGED: {status} - {note}")

    def suggest_facilitator(self, note):
        for key in FACILITATORS:
            if key in note:
                return FACILITATORS[key]
        return FACILITATORS["default"]

    def run_cycle(self):
        self.glasses.send_text("Status Check:\nOn Task or Off Task?")
        print("\nAssistant: Are you 'On Task' or 'Off Task'?")

        command = self.listen_to_voice()

        if not command:
            self.glasses.send_text("Didn't hear you.\nTry again.")
            return

        if "off task" in command:
            self.glasses.send_text("Why off task?\n(Briefly state reason)")
            print("Assistant: Why? (e.g., 'Distracting thoughts', 'Negative emotion')")

            reason = self.listen_to_voice() or "Unknown"
            suggestion = self.suggest_facilitator(reason)
            self.glasses.send_text(f"Strategy:\n{suggestion}")
            print(f"Strategy Suggestion: {suggestion}")
            self.log_behavior("Off Task", reason, suggestion)
            time.sleep(4)

        elif "on task" in command:
            self.glasses.send_text("Great job!\nKeep flowing.")
            self.log_behavior("On Task", "Focused", "None")

        elif "exit" in command:
            self.is_running = False
            self.glasses.send_text("Assistant\nDisconnected")

    def start(self):
        self.connect()
        while self.is_running:
            try:
                input("Press Enter to log status (or Ctrl+C to quit)...")
                self.run_cycle()
            except KeyboardInterrupt:
                print("Shutting down.")
                self.is_running = False


def main():
    app = FocusAssistant()
    app.start()


if __name__ == "__main__":
    main()
