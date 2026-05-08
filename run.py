import os
import webbrowser
from pathlib import Path
from threading import Timer

import uvicorn

PORT = int(os.environ.get("PORT", "8765"))
RELOAD = os.environ.get("RELOAD", "1") != "0"  # set RELOAD=0 to disable
ROOT = Path(__file__).resolve().parent


def open_browser():
    webbrowser.open(f"http://127.0.0.1:{PORT}")


if __name__ == "__main__":
    if not os.environ.get("UVICORN_NO_BROWSER"):
        Timer(1.5, open_browser).start()
    uvicorn.run(
        "backend.app:app",
        host="127.0.0.1",
        port=PORT,
        reload=RELOAD,
        reload_dirs=[str(ROOT / "backend"), str(ROOT / "frontend")] if RELOAD else None,
        log_level="info",
    )
