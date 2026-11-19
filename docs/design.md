<!-- SPDX-License-Identifier: LGPL-3.0-only -->
<!-- SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev> -->

# Design

## Scope

The deck is a client for the Telegram Bot API: a `Bot` (token and API base
URL) sends messages (`sendMessage`, `sendMessageWith`,
`sendMessageWithKeyboard`), photos by URL or file id (`sendPhoto`), local
files (`sendPhotoFile`, `sendDocumentFile`) and chat actions, identifies
itself with `getMe`, and receives updates by long polling (`getUpdates`,
`getUpdatesRaw`) with button presses read by `parseCallbackQuery` and
acknowledged by `answerCallbackQuery`.

It deliberately covers a bot's everyday loop, not the whole API:

- **No webhooks.** Receiving updates through a webhook needs a public HTTPS
  server; long polling works from anywhere, including behind NAT. A program
  that runs a server can decode the same update JSON with `parseUpdate`.
- **No typed model of every update and message kind.** `Update` and
  `Message` carry the text-relevant fields; `getUpdatesRaw` hands out the raw
  JSON of each update so anything else (edits, media, chat members) is still
  reachable with `json`.
- **No chat administration, payments, games, stickers or inline mode.** Each
  is a call through the same request core when someone needs it.
- **No rate limiting or retry.** Flood control is reported (`retryAfter`) and
  left to the caller.

## Decisions

- **A deck, not a bundled module.** A client for one vendor's API belongs in
  the deck ecosystem. The deck is one of the bundled modules that `jennifer`
  moves out (M30.1 in its milestones, formerly M28.32) and keeps the module's
  surface, so migrating changes only the import. It adds `getUpdatesRaw` and
  `parseUpdate`, without which button presses could not be received, and
  throws a `telegram` error where the module threw a `json` one for a field
  of the wrong type.
- **No state but the `Bot`.** The caller holds the bot and the polling
  `offset` and advances it past each processed update; the deck keeps no
  session, so a restart resumes where the caller says.
- **Form-encoded calls, multipart uploads.** Ordinary methods POST
  `application/x-www-form-urlencoded` parameters. File uploads build a
  `multipart/form-data` body (`buildUpload`, pure and testable) and send it as
  raw bytes, since a string round trip would corrupt binary files.
- **Long-poll deadline follows the poll.** `getUpdates` sets the HTTP
  deadline a few seconds beyond the long-poll `timeout`; other calls use a
  30-second deadline.
- **Keyboards as values.** `urlButton` and `inlineButton` build a `Button`
  with exactly one action, and `renderInlineKeyboard` turns rows of them into
  the `reply_markup` JSON.
- **`botWith` takes any base URL**, for a self-hosted Bot API server or a
  test endpoint.

## Errors

`TelegramError` (kind `"telegram"`) is the one struct for every error of that
kind:

- an API error (`{"ok": false}`) carries Telegram's `description` as the
  message, its `errorCode`, the reply's HTTP `status`, and the parameters
  `retryAfter` (flood control, `429`) and `migrateToChatId` (a group that
  became a supergroup);
- a reply that is not JSON, lacks `ok` or has a field of the wrong type, and
  a transport failure with malformed framing, have `errorCode` 0.

The generic kinds go on instead: a socket failure (refused, reset, failed
lookup, TLS) is `http`'s `net.NetError` (kind `"net"`, with `op`, `reason`,
`sent` and `replied`); a reply over `http`'s body cap or past `json`'s
decoding caps is kind `"limit"`, a deadline `"timeout"`, a connection closed
mid-answer `"closed"` and a cancelled task `"cancelled"`. A caller can so
tell a stalled long poll from an API error by its kind.

## Security and limits

- **The token is in the URL path** (`/bot<TOKEN>/<method>`), as the Bot API
  requires, so any text that may carry the URL is passed through
  `redactToken`: every transport error the deck rethrows, the generic kinds
  and the `net.NetError` included (its message names only the host and port, and is redacted all
  the same, with its kind and fields kept). `redactToken` also catches the
  token with its `:` percent-encoded, and is exported for the caller's own
  logs.
- **The base URL is used as given.** The default is
  `https://api.telegram.org`; a plain `http://` base passed to `botWith`
  sends the token in the clear, which is meant only for a local test server
  or a self-hosted API server on a trusted network.
- **Hostile replies.** A proxy's HTML error page, a missing `ok` or a
  wrongly typed field is a `telegram` error, never a raw `json` one; body
  size and JSON nesting are capped by `http` and `json` (kind `"limit"`).
- **Uploads read the whole file** into memory before sending; Telegram's own
  upload limits apply on its side.

## Testing and validation

`src/telegram_test.j` covers form encoding, response checking (API errors
with every parameter, missing `ok`, wrongly typed fields), user, message,
update and callback parsing, keyboards, multipart bodies and token
redaction. The API calls go to an `httpd` server on a loopback port through
`botWith`, which checks the method path, form fields and uploaded bytes and
answers with canned Bot API replies, including a non-JSON proxy page. A
refused connection is shown to arrive as a `net.NetError` without the
token, and an over-deep reply as kind `"limit"`.

The tests never reach Telegram. `examples/send.j` sends a message when
`TELEGRAM_BOT_TOKEN` and `TELEGRAM_CHAT_ID` are set and does nothing
otherwise, so CI runs it offline.

## Known limitations and open questions

- `Update` drops every update that is not a text message; use
  `getUpdatesRaw`.
- No helper sleeps on `retryAfter`; the caller decides.

## Dependencies on the interpreter

- The floor is `>=0.26.0`, the release that deprecates the bundled module
  (M30.1).
- `http.requestRawBody` for binary uploads, and `multipart`, both of which
  stay in the interpreter after the bundled modules are removed.
- Thrown error structs (M28.50, M28.51); kind `"limit"` for caps (M28.54,
  M28.68); `net.NetError` for socket failures (M28.65). On an interpreter
  without transport error kinds a socket failure is a `TelegramError`.
- `http` needs the `net` capability, so the deck runs on the default
  `jennifer` binary; `jennifer-tiny` has no network driver.
