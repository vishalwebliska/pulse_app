# Pulse (Flutter) — Build Progress

_Cross-platform Teams/Slack-style client. Repo: `C:\flaxxa\pulse_app`._
_Last updated: 2026-11-03_

## ✅ Done
- **Auth** — login via Sanctum PAT (`/auth/mobile/login`); secure token store; MFA accounts routed to web.
- **Workspace switcher** — dropdown in the Chat app bar (shown with 2+ workspaces); switching updates `X-Tenant-ID` and reloads conversations.
- **Channels** — list + channel view + message composer.
- **Direct messages** — 1:1 and group DM (idempotent find-or-create); DM + channel lists in the Chat tab.
- **Create group** — named private channel + member picker.
- **People search** — "find people" directory search → start a DM.
- **@mentions** — composer autocomplete (collapsed-name token) + mention highlighting.
- **Live messages** — Reverb realtime (`message.sent`) + token-aware broadcasting auth (B3).
- **Reactions** — long-press emoji react; reaction chips with counts; tap to toggle.
- **Message actions** — long-press → Copy text, Delete (your own).
- **Threads / replies** — "N replies" indicator + thread view (root + replies + composer).
- **Message search** — scoped (in-channel, always available) + global (workspace-wide, plan-gated → shows upgrade notice on 402). Entry: Chat-tab search icon (global) + each channel's search button (scoped).
- **Local web preview** — `flutter build web` (local mode) served at `http://127.0.0.1:8099` for in-browser testing.

## 🔨 In progress
- _(nothing active — next slice TBD)_

## 📋 Left / planned
- Mentions / activity inbox (`GET /pulse/mentions`).
- Edit your own message (`PATCH /messages/{id}`, 10-min window).
- Pins + saved messages.
- Typing indicators / presence (online dots are already in the directory).
- Read-state / unread sync.
- Push notifications (Firebase/FCM) — needs device-token wiring (B5).
- Meetings tab (LiveKit/Google Meet) — needs backend B4.

## Environment / deploy
- App config (`lib/core/config.dart`) defaults to **prod** (`https://flaxxa.com`); `--dart-define=PULSE_ENV=local` points at `http://localhost:8000` + local Reverb for dev.
- Builds: Android (`flutter build apk --release --split-per-abi`), Windows (`flutter build windows --release`), macOS via GitHub Actions CI on push.
- **Pending (backend, user's git/deploy):** deploy mobile-auth **B1/B2/B3** to prod (`vishal → staging → main` + `route:clear && route:cache`). Until then, prod builds reach the login screen but can't sign in; test locally against `:8000`.

## Test accounts (local dev DB)
- `pulse.tester@flaxxa.test` / `PulseTest@2026` (user 26919)
- `pulse.tester2@flaxxa.test` / `PulseTest@2026` (user 26920)
- Workspace/tenant: `a321102b-25da-47ae-b23b-7ec7a1120644` ("Pulse Test Workspace")
