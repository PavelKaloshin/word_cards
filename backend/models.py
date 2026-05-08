"""
Pydantic schemas for API I/O. Internal storage is plain dicts (JSON-friendly).
"""
from __future__ import annotations

from typing import Literal, Optional

from pydantic import BaseModel, Field


Grade = Literal["good", "hard", "again"]
Direction = Literal["forward", "reverse"]
SessionMode = Literal["learn", "review"]


class WordEntry(BaseModel):
    word: str
    translation: Optional[str] = None
    note: Optional[str] = None


class AddWordsRequest(BaseModel):
    entries: list[WordEntry]


class AnswerRequest(BaseModel):
    grade: Grade
    direction: Direction
    typed_input: Optional[str] = None  # for typing mode


class StartSessionRequest(BaseModel):
    mode: SessionMode
    size: Optional[int] = None  # override config


class TypingCheckRequest(BaseModel):
    word_id: str
    typed: str


class WordPatch(BaseModel):
    note: Optional[str] = None
    translation: Optional[str] = None


class ParseTextRequest(BaseModel):
    text: str
