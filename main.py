"""
main.py — Entry point for the Gann backtest Telegram bot.

Modules:
  state.py       — global state, config, persistence
  market_data.py — OANDA REST candle fetching
  strategy.py    — Gann levels, trend filters, ATR, TP/SL
  backtest.py    — idealized Gann backtest engine
  telegram_ui.py — Telegram keyboards, messages, callback dispatch
"""

import asyncio
import os

from aiohttp import web

from state import bot_state, get_http, c_log, log_exception, load_bot_persistence
from telegram_ui import telegram_polling_loop, telegram_watchdog


_poll_task: asyncio.Task | None = None


async def supervised(coro_fn, *args, label: str = '') -> None:
    """Wrap a long-running coroutine with crash-restart + backoff."""
    global _poll_task
    _MAX_CONSECUTIVE_CRASHES = 10
    _MAX_BACKOFF_SECONDS = 120
    crash_count = 0
    while True:
        try:
            task = asyncio.current_task()
            if label == 'tg_polling':
                _poll_task = task
            await coro_fn(*args)
            crash_count = 0
        except asyncio.CancelledError:
            await asyncio.sleep(2)
        except Exception as e:
            crash_count += 1
            log_exception(
                f'supervised task "{label}" crashed (crash {crash_count}/{_MAX_CONSECUTIVE_CRASHES})', e
            )
            if crash_count >= _MAX_CONSECUTIVE_CRASHES:
                c_log(f'Supervised task "{label}" exceeded max crashes — stopping restarts.')
                return
            backoff = min(2 ** min(crash_count, 6), _MAX_BACKOFF_SECONDS)
            await asyncio.sleep(backoff)


async def health_handler(request: web.Request) -> web.Response:
    return web.Response(text='ok')


async def start_http_server() -> web.AppRunner:
    app = web.Application()
    app.router.add_get('/health', health_handler)
    port = int(os.environ.get('PORT', '8080'))
    runner = web.AppRunner(app)
    await runner.setup()
    site = web.TCPSite(runner, '0.0.0.0', port)
    await site.start()
    c_log(f'HTTP health server on :{port}')
    return runner


async def main() -> None:
    c_log('Gold Scalper Backtest Bot starting...')
    await load_bot_persistence()

    runner = await start_http_server()

    tasks = [
        asyncio.create_task(supervised(telegram_polling_loop, label='tg_polling'), name='tg_polling'),
        asyncio.create_task(supervised(telegram_watchdog, label='tg_watchdog'), name='tg_watchdog'),
    ]

    c_log('All background tasks launched (Telegram only — backtest on demand).')
    try:
        await asyncio.gather(*tasks)
    finally:
        await runner.cleanup()
        sess = get_http()
        if sess and not sess.closed:
            await sess.close()


if __name__ == '__main__':
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        c_log('Shutting down...')
