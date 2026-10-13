# High Society server

Tiny Node server (no dependencies, Node 18+) that deals the cards, enforces the rules and sends each player only their own hand.

## Run locally
    node server.js        # http://localhost:8080
    node test_server.js   # end-to-end tests

## Deploy (needs https for the iPhone app)
Any host that runs a Dockerfile or Node works. Examples:
- **Render**: New > Web Service > connect the repo/folder, runtime Docker. Free tier sleeps after idle, so the first request takes ~30s.
- **Fly.io**: `fly launch` in this folder, accept the Dockerfile, then `fly deploy`. Add a volume mounted at /data if you want games to survive restarts.
- **Railway**: New project > Deploy from folder; set PORT if asked.

Your server address is the https URL the host gives you. Type it into the app once; invite links carry it to friends.

## Environment variables
- `PORT` (default 8080)
- `DATA_DIR` where games.json is saved (default ./data). On a host with no persistent disk, games are lost on restart.
- `NO_PERSIST=1` keep games in memory only
- `POLL_MS` long-poll timeout, default 25000
- `TESTFLIGHT_URL` shown as an "Get the app" button on invite pages
- `APPLE_APP_ID` (TEAMID.bundleid) serves the apple-app-site-association file for Universal Links (needs a paid developer account)
