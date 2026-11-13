"""
Vercel Serverless Function Entry Point for MINH AN B2B AI AGENT
"""
import sys
import os

# Đảm bảo thư mục gốc dự án luôn nằm trong sys.path của Python runtime
ROOT_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
if ROOT_DIR not in sys.path:
    sys.path.insert(0, ROOT_DIR)

from main import app, application, handler

__all__ = ["app", "application", "handler"]

