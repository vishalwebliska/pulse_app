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
- **Message actions** — long-press → Copy, Edit (10-min window; shows an "(edited)" marker), or Delete (your own).
- **Threads / replies** — "N replies" indicator + thread view (root + replies + composer).
- **Message search** — scoped (in-channel, always available) + global (workspace-wide, plan-gated → shows upgrade notice on 402). Entry: Chat-tab search icon (global) + each channel's search button (scoped).
- **Flaxxa-web theme** — Inter font (google_fonts), Pulse orange `#F97316→#F59E0B` + navy-slate dark `#141C2E` (matching the web's design tokens), proper text sizing + AppBar/nav/input theming; fixed a message-text bug (Flutter's unstyled red/yellow `RichText` fallback → `Text.rich`).
- **Message timestamps** — show date + time ("Today 11:49 AM" / "Yesterday …" / "3 Nov, 11:49 AM").
- **Read state** — opening a conversation marks it read (`POST /channels/{id}/read`), clearing the unread badge (channels + DMs).
- **Activity inbox** — an **Activity** tab listing every @mention (unread/all toggle); tap to open the conversation + mark it read (`GET /pulse/mentions`, `PATCH /mentions/{id}/read`).
- **Pins** — pin/unpin a message (long-press), a 📌 indicator on pinned messages, and a per-conversation **Pinned** view (`POST`/`DELETE /messages/{id}/pin`, `GET /channels/{id}/pins`).
- **Saved messages** — bookmark any message (long-press → Save); view all of them in **Me → Saved messages** (`POST`/`DELETE /messages/{id}/save`, `GET /saved-messages`).
- **Typing indicators** — live "X is typing…" while others type (throttled `POST /pulse/typing/{id}` → `member.typing` over Reverb; 5s expiry).
- **Forward** — forward any message to another channel/DM with an optional note (`POST /messages/{id}/forward`).
- **Local web preview** — `flutter build web` (local mode) served at `http://127.0.0.1:8099` for in-browser testing.

## 🔨 In progress
- _(nothing active — next slice TBD)_

## 📋 Left / planned
- Presence online dots — needs joining the Reverb **presence channel**; HTTP `/presence/ping` alone does NOT drive the `online` flag (verified 2026-11-03).
- Read-state / unread sync.
- Push notifications (Firebase/FCM) — needs device-token wiring (B5).
- Meetings tab (LiveKit/Google Meet) — needs backend B4.

## Environment / deploy
- App config (`lib/core/config.dart`) defaults to **prod** (`https://flaxxa.com`); `--dart-define=PULSE_ENV=local` points at `http://localhost:8000` + local Reverb for dev.
- Builds: Android (`flutter build apk --release --split-per-abi`), Windows (`flutter build windows --release`), macOS via GitHub Actions CI on push.
- **Backend mobile-auth B1/B2/B3: DEPLOYED to prod ✅ (2026-11-03)** — `flaxxa.com/api/v1/auth/mobile/*` live (login 422 on empty body, broadcasting/auth 401); real flaxxa.com users sign in on the prod apps. Prod Reverb + Pulse chat API already live.

## Test accounts (local dev DB)
- `pulse.tester@flaxxa.test` / `PulseTest@2026` (user 26919)
- `pulse.tester2@flaxxa.test` / `PulseTest@2026` (user 26920)
- Workspace/tenant: `a321102b-25da-47ae-b23b-7ec7a1120644` ("Pulse Test Workspace")
