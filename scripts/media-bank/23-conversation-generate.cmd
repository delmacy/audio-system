@echo off
setlocal
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Invoke-ConversationGenerate.ps1" %*
exit /b %ERRORLEVEL%
