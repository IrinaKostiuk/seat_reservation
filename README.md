# Seat reservation — 40-minute task

Build a seat reservation server for one concert, in Elixir.

There are **100 seats**. Many fans try to grab seats at the same time.

## Requirements

1. A fan can `hold(seat, fan)` and `release(seat, fan)`. A seat can be held by only one fan at a time.
2. A held seat is released automatically after **10 seconds** unless `confirm(seat, fan)` is called.
3. Any process can `subscribe()` and receive a message whenever a seat changes state
   (`{:seat_event, seat, :held | :released | :confirmed, fan}`).
4. If one fan crashes or sends garbage, the other fans and the seat data must not be affected.
5. The server must stay responsive when 1,000 fans each try to hold a seat within one second.
6. Add UI

The function signatures and return values are fixed — see `lib/seat_reservation.ex`.
Everything else (which processes exist, who owns the state, how failures are handled) is your decision.

## Rules

- Use any AI assistant as much as you like, for anything: code, explanations, architecture.
- Keep your AI chat history; you'll be asked to share it (anonymised).
- Don't look at other participants' work.

## Run

```bash
mix compile
mix run load_test.exs
```

The load test starts 1,000 fans, fires a burst of holds, kills 10 holding fans, sends garbage,
checks a subscriber received events, waits for one hold to expire, and prints a scorecard.
It takes about 15 seconds. Run it as often as you like.

## Deliverable

- Your code, with the load test passing (or as close as you got).
- Replace this README's last section with **3–5 lines: how is your system structured, and why?**

## How it is structured and why

_(your answer here)_
