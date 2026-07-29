"""
market_data.py — OANDA REST candle fetching for the backtest engine.

Owns:
  - OANDA candle fetcher (fetch_candles, fetch_master_price)
"""

import asyncio
from datetime import datetime, timezone

import aiohttp
import pandas as pd

from state import (
    OANDA_TOKEN, OANDA_BASE_URL, OANDA_ACCOUNT, get_http, log_exception, _safe_float,
)

# ---------------------------------------------------------------------------
# OANDA FETCHER
# ---------------------------------------------------------------------------
_OANDA_GRAN = {
    '1m': 'M1', '2m': 'M2', '3m': 'M3', '4m': 'M4', '5m': 'M5', '6m': 'M6',
    '10m': 'M10', '15m': 'M15', '20m': 'M20', '30m': 'M30', '1h': 'H1', '2h': 'H2',
}
_oanda_sem: asyncio.Semaphore | None = None


def _get_oanda_sem() -> asyncio.Semaphore:
    global _oanda_sem
    if _oanda_sem is None:
        _oanda_sem = asyncio.Semaphore(3)
    return _oanda_sem


def _validated_candle(c: dict, symbol: str, granularity_str: str) -> dict | None:
    try:
        mid = c.get('mid')
        if not isinstance(mid, dict):
            raise ValueError(f"missing/invalid 'mid' field: {mid!r}")
        raw_time = c.get('time')
        if not raw_time:
            raise ValueError("missing 'time' field")
        o = float(mid['o']); h = float(mid['h']); l = float(mid['l']); c_ = float(mid['c'])
        vol = float(c.get('volume', 1.0) or 1.0)
        for v in (o, h, l, c_, vol):
            if v != v or v in (float('inf'), float('-inf')):
                raise ValueError(f"non-finite value in candle: {v!r}")
        return {
            'time': pd.Timestamp(raw_time).tz_convert('UTC'),
            'open': o, 'high': h, 'low': l, 'close': c_, 'volume': vol,
        }
    except (TypeError, ValueError, KeyError) as e:
        log_exception(f"_validated_candle [{symbol} {granularity_str}] -- skipping malformed candle", e)
        return None


async def fetch_candles(symbol: str, granularity_str: str, count: int = 5000,
                        end_time: datetime = None) -> list:
    gran_str = _OANDA_GRAN.get(granularity_str, 'M1')
    fetch_count = min(count, 120000)
    collected = []
    remaining = fetch_count
    headers = {'Authorization': f'Bearer {OANDA_TOKEN}', 'Content-Type': 'application/json'}
    url = f'{OANDA_BASE_URL}/instruments/{symbol}/candles'
    current_end = end_time if end_time else datetime.now(timezone.utc)

    while remaining > 0:
        chunk = min(remaining, 5000)
        params = {
            'granularity': gran_str,
            'count': chunk,
            'to': current_end.strftime('%Y-%m-%dT%H:%M:%S.000000000Z'),
            'price': 'M',
        }
        candles = []
        async with _get_oanda_sem():
            for attempt in range(6):
                try:
                    async with get_http().get(
                        url, headers=headers, params=params,
                        timeout=aiohttp.ClientTimeout(total=20),
                    ) as resp:
                        if resp.status == 200:
                            data = await resp.json()
                            candles = data.get('candles') or []
                            break
                        if resp.status == 429:
                            await asyncio.sleep(2 ** attempt)
                            continue
                        body = await resp.text()
                        log_exception(
                            f"fetch_candles [{symbol} {gran_str}]",
                            Exception(f"HTTP {resp.status}: {body[:200]}"),
                        )
                        break
                except Exception as e:
                    if attempt == 5:
                        log_exception(f"fetch_candles [{symbol} {gran_str}]", e)
                    else:
                        await asyncio.sleep(1.5 * (attempt + 1))
        if not candles:
            break
        parsed = []
        for c in candles:
            if not c.get('complete', True):
                continue
            vc = _validated_candle(c, symbol, gran_str)
            if vc:
                parsed.append(vc)
        if not parsed:
            break
        collected = parsed + collected
        remaining = fetch_count - len(collected)
        earliest = parsed[0]['time']
        current_end = earliest.to_pydatetime() if hasattr(earliest, 'to_pydatetime') else earliest
        if len(parsed) < chunk:
            break

    collected.sort(key=lambda c: c['time'])
    return collected[-count:] if count and len(collected) > count else collected


async def fetch_master_price(symbol: str) -> float | None:
    """Latest mid price from OANDA pricing endpoint (optional utility)."""
    headers = {'Authorization': f'Bearer {OANDA_TOKEN}', 'Content-Type': 'application/json'}
    url = f'{OANDA_BASE_URL}/accounts/{OANDA_ACCOUNT}/pricing'
    params = {'instruments': symbol}
    try:
        async with get_http().get(url, headers=headers, params=params,
                                   timeout=aiohttp.ClientTimeout(total=10)) as resp:
            if resp.status != 200:
                return None
            data = await resp.json()
            prices = data.get('prices') or []
            if not prices:
                return None
            p = prices[0]
            bids = p.get('bids') or [{}]
            asks = p.get('asks') or [{}]
            bid = _safe_float(bids[0].get('price') if bids else None)
            ask = _safe_float(asks[0].get('price') if asks else None)
            if bid and ask:
                return round((bid + ask) / 2.0, 5)
            return bid or ask or None
    except Exception as e:
        log_exception(f"fetch_master_price [{symbol}]", e)
        return None
