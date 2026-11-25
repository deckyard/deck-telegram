# @deckyard/telegram

[![test](https://github.com/deckyard/deck-telegram/actions/workflows/test.yml/badge.svg)](https://github.com/deckyard/deck-telegram/actions/workflows/test.yml)
[![Documentation](https://img.shields.io/badge/docs-github%20pages-blue)](https://deckyard.github.io/deck-telegram/)
[![release](https://img.shields.io/github/v/release/deckyard/deck-telegram)](https://github.com/deckyard/deck-telegram/releases/latest)

A [Telegram™ Bot API](https://core.telegram.org/bots/api) client for
[Jennifer](https://jennifer-lang.dev/) programs: send messages, photos and
files, attach inline keyboards, and poll for updates. Replaces the `telegram`
module of Jennifer's standard library (shipped since 0.18.0, deprecated from
0.26.0, removed in 0.28.0); the API is unchanged, only the import differs.

Up to 0.3.0 this deck was `@jennifer/telegram`. To switch, change the `[decks]`
entry to `"@deckyard/telegram" = "^0.4.0"` and the imports to `"@deckyard/telegram/"`.

**[Documentation](https://deckyard.github.io/deck-telegram/)**

## Install

```sh
jvc add @deckyard/telegram
```

This vendors the deck to `vendor/deckyard/telegram/`. Without `jvc`, unpack the
`src/` subtree of a release archive (`deckyard-telegram-<version>.tar.gz`) there.

## Usage

```jennifer
import "@deckyard/telegram/" as telegram;

def bot as telegram.Bot init telegram.bot(os.getEnv("TELEGRAM_BOT_TOKEN"));
telegram.sendMessage($bot, 12345678, "deploy finished");
```

`examples/send.j` sends a plain message and one with a URL button.

## Requirements

Jennifer 0.27.0 or newer and network access to the Telegram Bot API. Calls need
the default `jennifer` binary; the stock `jennifer-tiny` has no network driver.

## Development

```sh
tools/check-all.sh                   # the full gate, as CI runs it
jennifer test src/telegram_test.j      # the test overlay
tools/check-docs.sh                  # docs against the code
tools/pack.sh dist                   # build the release archive
```

## Licence

LGPL-3.0-only, see [LICENSE](LICENSE). Copyright (C) 2026 mplx &lt;mplx@jennifer-lang.dev&gt;.

`tools/check-headers.sh` checks every source file's SPDX header against
`deck.toml`.

## Trademarks

Telegram™ is a trademark of Telegram FZ-LLC. Other product and company names
may be trademarks of their respective owners. They are used only to identify
the products this deck works with. This deck is an independent project, not
affiliated with, sponsored or endorsed by Telegram FZ-LLC.
