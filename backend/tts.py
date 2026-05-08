"""
TTS via edge-tts (free, online). Caches by word_id.
"""
from __future__ import annotations

import asyncio
from pathlib import Path

import edge_tts


async def _synthesize(text: str, voice: str, dest: Path) -> None:
    communicate = edge_tts.Communicate(text=text, voice=voice)
    dest.parent.mkdir(parents=True, exist_ok=True)
    await communicate.save(str(dest))


def synthesize(text: str, voice: str, dest: Path) -> Path:
    """Sync wrapper. Always writes the file (overwrites existing)."""
    asyncio.run(_synthesize(text, voice, dest))
    return dest
