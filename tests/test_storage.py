"""
Atomicity & roundtrip for the JSON storage. No mocking — uses real tmp files.
"""
import json

from backend.storage import JsonStore, SessionsDB, WordsDB


class TestJsonStore:
    def test_default_when_missing(self, tmp_path):
        s = JsonStore(tmp_path / "nope.json", default={"x": 1})
        assert s.data == {"x": 1}

    def test_save_and_reload(self, tmp_path):
        path = tmp_path / "thing.json"
        s = JsonStore(path, default={"items": []})
        s.data["items"].append({"a": 1})
        s.save()
        # Reload from disk by creating a new store
        s2 = JsonStore(path, default={"items": []})
        assert s2.data == {"items": [{"a": 1}]}

    def test_replace(self, tmp_path):
        path = tmp_path / "thing.json"
        s = JsonStore(path, default={})
        s.replace({"new": "data"})
        s2 = JsonStore(path, default={})
        assert s2.data == {"new": "data"}

    def test_corrupt_json_falls_back_to_default(self, tmp_path):
        path = tmp_path / "broken.json"
        path.write_text("{not json{", encoding="utf-8")
        s = JsonStore(path, default={"safe": True})
        assert s.data == {"safe": True}
        assert path.with_suffix(".json.corrupt").exists()

    def test_atomic_write_doesnt_leave_garbage(self, tmp_path):
        path = tmp_path / "atomic.json"
        s = JsonStore(path, default={"v": 0})
        for i in range(5):
            s.data["v"] = i
            s.save()
        # Only the target file should exist (no .tmp residue)
        files = list(tmp_path.iterdir())
        assert len(files) == 1
        assert files[0].name == "atomic.json"


class TestWordsDB:
    def test_add_and_get(self, tmp_path):
        db = WordsDB(tmp_path / "words.json")
        db.add({"id": "x", "word_cyr": "хлеб"})
        assert db.get("x")["word_cyr"] == "хлеб"

    def test_update_returns_none_for_missing(self, tmp_path):
        db = WordsDB(tmp_path / "words.json")
        assert db.update("ghost", {"x": 1}) is None

    def test_update_persists(self, tmp_path):
        path = tmp_path / "words.json"
        db = WordsDB(path)
        db.add({"id": "x", "streak": 0})
        db.update("x", {"streak": 3})
        # Reload
        db2 = WordsDB(path)
        assert db2.get("x")["streak"] == 3

    def test_delete(self, tmp_path):
        db = WordsDB(tmp_path / "words.json")
        db.add({"id": "x"})
        assert db.delete("x") is True
        assert db.get("x") is None
        assert db.delete("ghost") is False


class TestSessionsDB:
    def test_append_and_recent(self, tmp_path):
        db = SessionsDB(tmp_path / "sessions.json")
        for i in range(5):
            db.append({"id": f"s{i}", "summary": {"shown": i}})
        recent = db.recent(3)
        assert len(recent) == 3
        assert [s["id"] for s in recent] == ["s2", "s3", "s4"]
