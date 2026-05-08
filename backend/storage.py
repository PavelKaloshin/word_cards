"""
Atomic JSON storage. Each mutation flushes the entire file via write-temp + rename.
For thousands of words this is fine; we don't need a real DB.
"""
from __future__ import annotations

import json
import os
import shutil
import tempfile
import threading
from pathlib import Path
from typing import Any

_LOCK = threading.RLock()


def _atomic_write(path: Path, data: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp_path = tempfile.mkstemp(prefix=path.name + ".", dir=str(path.parent))
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            json.dump(data, f, ensure_ascii=False, indent=2)
            f.flush()
            os.fsync(f.fileno())
        os.replace(tmp_path, path)
    except Exception:
        if os.path.exists(tmp_path):
            os.unlink(tmp_path)
        raise


def _read(path: Path, default: Any) -> Any:
    if not path.exists():
        return default
    try:
        with path.open("r", encoding="utf-8") as f:
            return json.load(f)
    except json.JSONDecodeError:
        backup = path.with_suffix(path.suffix + ".corrupt")
        shutil.copy(path, backup)
        return default


class JsonStore:
    """Thread-safe wrapper around a JSON file. Loads once, flushes on every mutation."""

    def __init__(self, path: Path, default: Any):
        self.path = Path(path)
        self._default = default
        with _LOCK:
            self._data = _read(self.path, default)

    @property
    def data(self) -> Any:
        return self._data

    def save(self) -> None:
        with _LOCK:
            _atomic_write(self.path, self._data)

    def replace(self, new_data: Any) -> None:
        with _LOCK:
            self._data = new_data
            _atomic_write(self.path, self._data)


class WordsDB(JsonStore):
    """words keyed by id."""

    def __init__(self, path: Path):
        super().__init__(path, default={"words": {}})

    @property
    def words(self) -> dict[str, dict]:
        return self._data["words"]

    def add(self, word: dict) -> None:
        with _LOCK:
            self._data["words"][word["id"]] = word
            self.save()

    def update(self, word_id: str, patch: dict) -> dict | None:
        with _LOCK:
            w = self._data["words"].get(word_id)
            if w is None:
                return None
            w.update(patch)
            self.save()
            return w

    def delete(self, word_id: str) -> bool:
        with _LOCK:
            if word_id in self._data["words"]:
                del self._data["words"][word_id]
                self.save()
                return True
            return False

    def get(self, word_id: str) -> dict | None:
        return self._data["words"].get(word_id)

    def all(self) -> list[dict]:
        return list(self._data["words"].values())


class SessionsDB(JsonStore):
    """append-only session history."""

    def __init__(self, path: Path):
        super().__init__(path, default={"sessions": []})

    def append(self, session: dict) -> None:
        with _LOCK:
            self._data["sessions"].append(session)
            self.save()

    def recent(self, n: int = 20) -> list[dict]:
        return list(self._data["sessions"][-n:])
