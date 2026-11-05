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
- **Message timestamps** — per-message clock time ("11:49 AM"); the date lives in the day separator.
- **Web-matched chat UI** — rebuilt the conversation to mirror the Pulse web app (`ChannelView`/`MessageRow`): **chat-bubble layout** (own messages = orange `#F97316` right-aligned bubbles, others = left surface bubbles with grouped-corner tails), **round gradient avatars** (deterministic per-user palette) on the first message of each run, author name above others' runs, **pill day-dividers** (Today / Yesterday / weekday / date), same-author grouping with a **60-min** gap break, and one timestamp per same-minute burst.
- **Desktop message actions** — on Windows/macOS (mouse, no long-press) a **hover toolbar** (quick-react emojis · Reply · More) and **right-click** open the message actions; long-press still works on Android/iOS. Shared `HoverActions` widget (`hover_actions.dart`). The **thread/replies view** has the same actions (react, copy, save, pin, forward, edit/delete your own) + reaction chips, via the same hover/right-click/long-press. The hover bar wraps the whole message row (paints above the avatar, never clipped) and author names have more padding.
- **Composer formatting toolbar** — a Markdown formatting row above the message box (bold · italic · strikethrough · inline code · link · bullet/numbered list · quote), mirroring the web composer; shared `ComposerToolbar` used by the channel + thread composers.
- **Collapsible sidebar** — on wide screens (desktop/tablet) a Teams/Slack-style left rail (Chat · Activity · Meetings · Me) in Pulse orange with an expand/collapse toggle, replacing the bottom tabs; phones keep the bottom nav (`home_shell.dart`).
- **Optimistic send** — a sent message appears instantly with a faint "Sending…" state and the composer clears immediately; it flips to confirmed when the API responds (reconciled against the Reverb echo so it never double-shows), or to a red "Not sent — tap to retry" on failure. Long-press actions are disabled on not-yet-confirmed messages.
- **Read state** — opening a conversation marks it read (`POST /channels/{id}/read`), clearing the unread badge (channels + DMs).
- **Activity inbox** — an **Activity** tab listing every @mention (unread/all toggle); tap to open the conversation + mark it read (`GET /pulse/mentions`, `PATCH /mentions/{id}/read`).
- **Pins** — pin/unpin a message (long-press), a 📌 indicator on pinned messages, and a per-conversation **Pinned** view (`POST`/`DELETE /messages/{id}/pin`, `GET /channels/{id}/pins`).
- **Saved messages** — bookmark any message (long-press → Save); view all of them in **Me → Saved messages** (`POST`/`DELETE /messages/{id}/save`, `GET /saved-messages`).
- **Typing indicators** — live "X is typing…" while others type (throttled `POST /pulse/typing/{id}` → `member.typing` over Reverb; 5s expiry).
- **Forward** — forward any message to another channel/DM with an optional note (`POST /messages/{id}/forward`).
- **Channel details** — tap a channel's name → topic, member list + roles, **Add people** (private), and **Leave channel** (`GET /channels/{id}`, `GET`/`POST /channels/{id}/members`, `POST /channels/{id}/leave`).
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
- **App icon**: the Flaxxa Pulse mark (orange orb + waveform) via `flutter_launcher_icons` (source `assets/icon/app_icon.png` + adaptive `app_icon_foreground.png`). Regenerate with `dart run flutter_launcher_icons`.
- **Builds (CI)**: a push to `main` builds **macOS** (`macos.yml`), **Windows** (`windows.yml`) and **Android** split-ABI APKs (`android.yml`) on GitHub-hosted runners → downloadable artifacts on the repo's **Actions** tab (mac can't build on the local Windows box, so CI is the path for all three). Local builds remain possible when RAM allows.
- **Backend mobile-auth B1/B2/B3: DEPLOYED to prod ✅ (2026-11-03)** — `flaxxa.com/api/v1/auth/mobile/*` live (login 422 on empty body, broadcasting/auth 401); real flaxxa.com users sign in on the prod apps. Prod Reverb + Pulse chat API already live.

## Test accounts (local dev DB)
- `pulse.tester@flaxxa.test` / `PulseTest@2026` (user 26919)
- `pulse.tester2@flaxxa.test` / `PulseTest@2026` (user 26920)
- Workspace/tenant: `a321102b-25da-47ae-b23b-7ec7a1120644` ("Pulse Test Workspace")
