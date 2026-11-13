"""
Python Server Entrypoint for MINH AN B2B AI AGENT
Compatible with Localhost (uvicorn) and Vercel Serverless Functions
"""
import os
import uvicorn
from main import app, application, handler

if __name__ == "__main__":
    port = int(os.environ.get("PORT", 8080))
    print(f"🚀 MINH AN B2B AI AGENT (FastAPI Server) đang chạy tại: http://localhost:{port}/")
    uvicorn.run("main:app", host="0.0.0.0", port=port, reload=True)
