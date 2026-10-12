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

## Run the Phoenix UI

With Docker (no local Elixir or Node installation needed):

```bash
docker compose up --build
```

Open **http://localhost:4000**. Stop with Ctrl+C, then `docker compose down`.
Rebuild with the same command after editing the source.

With Elixir 1.15+ and Erlang installed:

```bash
mix local.hex --force
mix local.rebar --force
mix deps.get
mix phx.server
```

Pick a seat to hold it, then confirm within 10 seconds. The map updates live across
browsers. Tabs in the same browser share their reservations; use a private window
or a different browser to try competing fans. Confirmed seats survive refreshes.
Closing the last connected tab releases unconfirmed holds once its disconnect is
detected. Reservations and browser identities are in memory and reset on server
restart; clearing browser cookies also loses access to that browser's reservations.

The UI serves its JavaScript from the locked Phoenix dependencies and needs no
asset build or external CDN. This is a local development setup. Production mode
requires `SECRET_KEY_BASE` and `PHX_HOST`; set `PHX_SERVER=true` to start the endpoint
outside `mix phx.server`.

## Run the checks

```bash
docker compose run --rm web mix test
docker compose run --rm web mix run load_test.exs
```

Or locally:

```bash
mix format --check-formatted
mix compile --warnings-as-errors
mix test
mix run load_test.exs
```

The load test starts 1,000 fans, fires a burst of holds, kills 10 holding fans, sends garbage,
checks a subscriber received events, waits for one hold to expire, and prints a scorecard.
It takes about 15 seconds. Run it as often as you like.

## Deliverable

- Your code, with the load test passing (or as close as you got).
- Replace this README's last section with **3–5 lines: how is your system structured, and why?**

## How it is structured and why

One supervised GenServer owns all 100 seats and serializes requests, preventing double bookings.
Each hold has a 10-second monotonic deadline and a uniquely tagged timer, so stale timers cannot release newer holds.
Fans are monitored, never linked: a crash releases their active holds while confirmed reservations remain.
Phoenix LiveView subscribes to seat events; monitored browser-session workers preserve ownership across refreshes and release holds on disconnect.
State is in memory and resets on server restart; one owner keeps this small concert simple and responsive.
