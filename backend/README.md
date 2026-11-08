# Linky extraction API

Run locally from this directory:

```powershell
python -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -r requirements.txt
uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
```

The Android app packages its yt-dlp extractor and runs it directly on the phone; it does not call this server for media extraction. This FastAPI API is retained for optional future server-side features. `/api/extract` can also use yt-dlp when the backend dependencies are installed. Keep this service on a trusted network if you run it. Telegram bot credentials are read from backend environment variables and must never be put in the Android app.
