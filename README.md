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

## Web UI (Phoenix LiveView)

To launch the real-time interactive Phoenix LiveView dashboard:

```bash
mix run --no-halt
# or
iex -S mix
```

Open [http://localhost:4000](http://localhost:4000) in your browser.

## How it is structured and why

- **Independent Seat GenServers**: Each of the 100 seats is managed by its own GenServer process (`SeatReservation.Seat`), enabling concurrent lock-free operations across seats, automatic hold expiration timers, and fan monitoring via `Process.monitor/1`.
- **Fault Isolation**: With seats supervised individually (`:one_for_one`), a crash or failure in one seat or fan cannot affect other seats or fans.
- **Concurrent ETS Snapshot**: A shared ETS table (`:seat_reservation_seats` with `read_concurrency: true`) is updated on every state transition, enabling O(1) concurrent non-blocking reads for `SeatReservation.seats/0`.
- **Decoupled PubSub**: An OTP `Registry` with duplicate keys (`SeatReservation.Subscribers`) handles lightweight, fast event broadcasting (`{:seat_event, seat, state, fan}`) to all subscribed fans without blocking reservation workflows.
- **Real-Time Phoenix LiveView UI**: An interactive web interface (`SeatReservationWeb.SeatLive`) rendered over WebSocket on port 4000, displaying real-time seat availability, live event logs, and user controls (Hold, Confirm, Release).
