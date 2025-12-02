import os
import csv
import tempfile
from tools.focus_assistant import FocusAssistant, DATA_FILE, FACILITATORS


def test_suggest_facilitator_matches():
    app = FocusAssistant()
    assert app.suggest_facilitator('distracting thoughts about dinner') == FACILITATORS['distracting thoughts']
    assert app.suggest_facilitator('I feel fatigue') == FACILITATORS['fatigue']
    assert app.suggest_facilitator('completely unknown thing') == FACILITATORS['default']


def test_log_behavior_creates_csv(tmp_path):
    # Change data file to a temp path for this test
    tmp_file = tmp_path / 'tmp_log.csv'
    try:
        # monkeypatch the module-level DATA_FILE variable
        import importlib, tools.focus_assistant as fa
        importlib.reload(fa)
        fa.DATA_FILE = str(tmp_file)

        app = FocusAssistant()
        app.log_behavior('On Task', 'Focused', 'None')

        assert tmp_file.exists()
        with open(tmp_file, newline='') as f:
            r = csv.DictReader(f)
            rows = list(r)
            assert len(rows) == 1
            assert rows[0]['status'] == 'On Task'
    finally:
        if tmp_file.exists():
            tmp_file.unlink()


def test_run_cycle_off_task(monkeypatch, tmp_path):
    # Simulate voice responses: 'off task' -> 'distracting thoughts'
    responses = iter(['off task', 'distracting thoughts'])

    app = FocusAssistant()

    # force data file into tmp path
    import importlib, tools.focus_assistant as fa
    importlib.reload(fa)
    fa.DATA_FILE = str(tmp_path / 'log.csv')

    monkeypatch.setattr(app, 'listen_to_voice', lambda: next(responses, None))
    # run a single cycle
    app.run_cycle()

    # The CSV should contain 'Off Task'
    assert os.path.exists(fa.DATA_FILE)
    with open(fa.DATA_FILE) as f:
        lines = f.read()
        assert 'Off Task' in lines


def test_run_cycle_on_task(monkeypatch, tmp_path):
    # Simulate voice response: 'on task'
    app = FocusAssistant()

    import importlib, tools.focus_assistant as fa
    importlib.reload(fa)
    fa.DATA_FILE = str(tmp_path / 'log.csv')

    monkeypatch.setattr(app, 'listen_to_voice', lambda: 'on task')
    app.run_cycle()

    assert os.path.exists(fa.DATA_FILE)
    with open(fa.DATA_FILE) as f:
        assert 'On Task' in f.read()
