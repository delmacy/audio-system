# Local development supervisor

From the repository root, run:

powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\dev\Start-AudioSystemDev.ps1

Default behavior:
- checks origin/main every 20 seconds;
- pulls only with git pull --ff-only;
- never pulls over local uncommitted changes;
- starts the Vite frontend;
- starts scripts/player/timeline_api.py;
- lets Vite HMR refresh ordinary frontend source changes;
- restarts the timeline API when scripts/player/*.py changes;
- runs npm install when frontend package files change;
- restarts Vite when its runtime/dependency configuration changes;
- writes child process logs under runs/dev-supervisor/.

Useful options:
- -PollSeconds 10
- -NoAutoSync
- -NoFrontend
- -NoTimelineApi

The supervisor intentionally pauses auto-pull if the working tree is dirty or the checked-out branch is not main. It does not stash, reset, force checkout, or overwrite local work.
