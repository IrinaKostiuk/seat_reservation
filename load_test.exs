# Run with:  mix run load_test.exs
#
# Starts 1000 fan processes, fires a burst of holds within ~1 second, crashes
# 10 fans mid-hold, sends garbage, waits for one hold to expire, and prints a
# scorecard. Nothing here depends on how you structured your system — only on
# the public API in lib/seat_reservation.ex.

defmodule LoadTest do
  @fans 1_000
  @seats SeatReservation.seat_count()
  @expiry SeatReservation.hold_timeout_ms()

  def run do
    IO.puts("\n== seat reservation load test ==\n")

    observer = start_observer()
    coordinator = self()

    fans =
      for i <- 1..@fans do
        spawn(fn -> fan_loop(i, coordinator) end)
      end

    # ---- 1. burst: every fan tries to hold a random seat at once ------------
    seat_for = fn i -> rem(i - 1, @seats) + 1 end
    t0 = System.monotonic_time(:millisecond)
    Enum.each(fans, fn pid -> send(pid, {:go, seat_for.(:erlang.phash2(pid, @fans) + 1)}) end)

    results = collect(length(fans), 5_000, [])
    burst_ms = System.monotonic_time(:millisecond) - t0

    oks = for {_pid, seat, :ok, _lat} <- results, do: seat
    latencies = for {_pid, _seat, _res, lat} <- results, do: lat
    crashed_calls = Enum.count(results, fn {_, _, res, _} -> match?({:crashed, _}, res) end)
    double_booked = oks -- Enum.uniq(oks)

    # ---- 2. crash 10 fans that are holding a seat --------------------------
    holders = for {pid, seat, :ok, _} <- results, do: {pid, seat}
    victims = Enum.take(holders, 10)
    Enum.each(victims, fn {pid, _} -> Process.exit(pid, :kill) end)
    Process.sleep(300)

    server_alive_after_crash = api_alive?()
    fans_alive = Enum.count(fans, &Process.alive?/1)

    victim_seats_freed =
      case safe(fn -> SeatReservation.seats() end) do
        {:ok, seats} -> Enum.count(victims, fn {_, seat} -> Map.get(seats, seat) == :free end)
        _ -> :unknown
      end

    # ---- 3. garbage in ------------------------------------------------------
    garbage_ok =
      [fn -> SeatReservation.hold(:banana, self()) end,
       fn -> SeatReservation.hold(0, self()) end,
       fn -> SeatReservation.hold(@seats + 1, self()) end,
       fn -> SeatReservation.confirm(1, :not_a_pid) end,
       fn -> SeatReservation.release(-5, self()) end]
      |> Enum.map(fn f -> match?({:ok, _}, safe(f)) end)
      |> Enum.all?()

    server_alive_after_garbage = api_alive?()

    # ---- 4. events reached a subscriber ------------------------------------
    send(observer, {:report, self()})
    events_seen = receive do {:events, n} -> n after 1_000 -> :unknown end

    # ---- 5. hold expiry -----------------------------------------------------
    IO.puts("waiting #{div(@expiry, 1000)}s for a hold to expire...")
    expiry_ok =
      with {:ok, seats} <- safe(fn -> SeatReservation.seats() end),
           {seat, :free} <- Enum.find(seats, fn {_, s} -> s == :free end) || {nil, nil},
           true <- seat != nil,
           {:ok, :ok} <- safe(fn -> SeatReservation.hold(seat, self()) end) do
        Process.sleep(@expiry + 1_000)
        case safe(fn -> SeatReservation.seats() end) do
          {:ok, s} -> Map.get(s, seat) == :free
          _ -> false
        end
      else
        _ -> :unknown
      end

    # ---- scorecard ----------------------------------------------------------
    IO.puts("""

    BURST (#{@fans} fans, #{@seats} seats)
      responses received        #{length(results)} / #{@fans}
      holds succeeded           #{length(oks)}  (max possible: #{@seats})
      double bookings           #{length(double_booked)}   #{mark(double_booked == [])}
      calls that crashed        #{crashed_calls}          #{mark(crashed_calls == 0)}
      burst wall time           #{burst_ms} ms
      p50 / p95 / max latency   #{pct(latencies, 50)} / #{pct(latencies, 95)} / #{Enum.max(latencies, fn -> 0 end)} ms

    FAULT ISOLATION
      killed 10 holding fans; server still answering   #{mark(server_alive_after_crash)}
      other fans still alive                            #{fans_alive} / #{@fans - length(victims)}  #{mark(fans_alive == @fans - length(victims))}
      seats of killed fans freed                        #{victim_seats_freed} / 10  #{soft(victim_seats_freed == 10)}

    GARBAGE INPUT
      bad calls returned errors instead of crashing    #{mark(garbage_ok)}
      server still answering afterwards                #{mark(server_alive_after_garbage)}

    EVENTS
      events received by a subscriber during burst     #{events_seen}  #{soft(is_integer(events_seen) and events_seen >= length(oks))}

    EXPIRY
      unconfirmed hold freed after #{div(@expiry, 1000)}s                 #{mark(expiry_ok == true)}
    """)
  end

  # -- fans --------------------------------------------------------------------

  defp fan_loop(_i, coordinator) do
    receive do
      {:go, seat} ->
        t = System.monotonic_time(:millisecond)
        res = safe(fn -> SeatReservation.hold(seat, self()) end)
        lat = System.monotonic_time(:millisecond) - t
        send(coordinator, {:result, self(), seat, unwrap(res), lat})
        # stay alive holding the seat so we can be crashed later
        receive do
          :stop -> :ok
        end
    end
  end

  defp unwrap({:ok, v}), do: v
  defp unwrap(other), do: other

  defp collect(0, _timeout, acc), do: acc

  defp collect(n, timeout, acc) do
    receive do
      {:result, pid, seat, res, lat} -> collect(n - 1, timeout, [{pid, seat, res, lat} | acc])
    after
      timeout -> acc
    end
  end

  # -- observer ---------------------------------------------------------------

  defp start_observer do
    parent = self()

    pid =
      spawn(fn ->
        safe(fn -> SeatReservation.subscribe() end)
        send(parent, :subscribed)
        observe(0)
      end)

    receive do :subscribed -> :ok after 1_000 -> :ok end
    pid
  end

  defp observe(n) do
    receive do
      {:seat_event, _seat, _kind, _fan} -> observe(n + 1)
      {:report, to} -> send(to, {:events, n}); observe(n)
    end
  end

  # -- helpers ----------------------------------------------------------------

  defp api_alive? do
    match?({:ok, m} when is_map(m), safe(fn -> SeatReservation.seats() end))
  end

  defp safe(fun) do
    try do
      {:ok, fun.()}
    rescue
      e -> {:crashed, Exception.message(e)}
    catch
      :exit, reason -> {:crashed, {:exit, reason}}
      kind, reason -> {:crashed, {kind, reason}}
    end
  end

  defp pct([], _), do: 0

  defp pct(list, p) do
    sorted = Enum.sort(list)
    idx = min(length(sorted) - 1, round(length(sorted) * p / 100))
    Enum.at(sorted, idx)
  end

  defp mark(true), do: "PASS"
  defp mark(_), do: "FAIL"
  defp soft(true), do: "ok"
  defp soft(_), do: "(check)"
end

LoadTest.run()
