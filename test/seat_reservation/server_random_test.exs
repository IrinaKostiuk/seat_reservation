defmodule SeatReservation.ServerRandomTest do
  @moduledoc """
  Randomized concurrency tests. Several drivers run random operations
  (including invalid ones) through their own fans, while fans are killed and
  holds expire. The operation sequence derives from the ExUnit seed, so
  `mix test --seed N` replays it; thread scheduling still varies between runs.
  """
  use SeatReservation.ServerCase, async: true

  @moduletag hold_timeout_ms: 30

  @drivers 4
  @fans_per_driver 5
  @ops_per_driver 400

  test "every transition is legal and produces exactly one event", %{server: server} do
    seed = ExUnit.configuration()[:seed]
    checker = check_consistency_continuously(server)

    run_drivers(server, seed)
    stop_checker(checker)
    final = settle(server)

    replayed = Enum.reduce(drain_events(), all_free(), &apply_event(&1, &2, seed))
    assert replayed == final, "seed #{seed}: events do not replay to the final state"
  end

  test "no confirmed sale is lost when the server crashes repeatedly", %{server: server} do
    seed = ExUnit.configuration()[:seed]
    # The supervisor allows 3 restarts in 5 s, so the server is killed twice.
    crasher = Task.async(fn -> Enum.map(1..2, fn _ -> kill_after(server, 150) end) end)

    confirmed = run_drivers(server, seed)
    drivers_done = System.monotonic_time(:millisecond)
    kill_times = Task.await(crasher)
    assert Enum.all?(kill_times, &(&1 < drivers_done)), "the drivers finished before the kills"
    final = settle(server)

    for {seat, fan} <- confirmed do
      assert final[seat] == {:confirmed, fan}, "seed #{seed}: lost the sale of seat #{seat}"
    end
  end

  # Runs the drivers concurrently. Returns the {seat, fan} pairs whose
  # confirmation was acknowledged and never released.
  defp run_drivers(server, seed) do
    1..@drivers
    |> Enum.map(fn i -> Task.async(fn -> drive(server, {seed, i, 0}) end) end)
    |> Enum.map(&Task.await(&1, 30_000))
    |> Enum.reduce(MapSet.new(), &MapSet.union/2)
  end

  defp drive(server, seed) do
    :rand.seed(:exsss, seed)
    fans = for _ <- 1..@fans_per_driver, do: TestFan.start()

    {_fans, confirmed} =
      Enum.reduce(1..@ops_per_driver, {fans, MapSet.new()}, fn _, acc -> step(server, acc) end)

    confirmed
  end

  defp step(server, {fans, confirmed}) do
    fan = Enum.random(fans)
    seat = Enum.random([:rand.uniform(100), :rand.uniform(100), 0, 101, :banana])

    case :rand.uniform(100) do
      n when n <= 45 ->
        TestFan.hold(fan, server, seat)
        {fans, confirmed}

      n when n <= 70 ->
        case TestFan.confirm(fan, server, seat) do
          :ok -> {fans, MapSet.put(confirmed, {seat, fan})}
          _error_or_exit -> {fans, confirmed}
        end

      n when n <= 90 ->
        # An exit (server restarting) may or may not have released the seat.
        TestFan.release(fan, server, seat)
        {fans, MapSet.delete(confirmed, {seat, fan})}

      n when n <= 95 ->
        Process.exit(fan, :kill)
        {List.replace_at(fans, Enum.find_index(fans, &(&1 == fan)), TestFan.start()), confirmed}

      _n ->
        Process.sleep(:rand.uniform(30))
        {fans, confirmed}
    end
  end

  # Checks the server's memory against its table every few milliseconds while
  # the drivers run.
  defp check_consistency_continuously(server) do
    Task.async(fn ->
      Stream.repeatedly(fn ->
        assert_consistent(server)

        receive do
          :stop -> :stop
        after
          5 -> :continue
        end
      end)
      |> Enum.find(&(&1 == :stop))
    end)
  end

  defp stop_checker(checker) do
    send(checker.pid, :stop)
    Task.await(checker)
  end

  # Waits until every hold has expired or been freed, then checks the final
  # state. The drivers have finished, so their fans are gone.
  defp settle(server) do
    eventually(fn ->
      Enum.all?(Server.seats(server), fn {_seat, state} -> not match?({:held, _}, state) end)
    end)

    assert_consistent(server)
    Server.seats(server)
  end

  # Kills the server after `ms` and returns when that happened.
  defp kill_after(server, ms) do
    Process.sleep(ms)
    Process.exit(Process.whereis(server), :kill)
    System.monotonic_time(:millisecond)
  end

  defp drain_events(acc \\ []) do
    receive do
      {:seat_event, _seat, _kind, _fan} = event -> drain_events([event | acc])
    after
      0 -> Enum.reverse(acc)
    end
  end

  defp all_free, do: Map.new(1..100, &{&1, :free})

  defp apply_event({:seat_event, seat, kind, fan} = event, seats, seed) do
    next =
      case {kind, seats[seat]} do
        {:held, :free} ->
          {:held, fan}

        {:confirmed, {:held, ^fan}} ->
          {:confirmed, fan}

        {:released, {:held, ^fan}} ->
          :free

        {:released, {:confirmed, ^fan}} ->
          :free

        {_kind, current} ->
          flunk("seed #{seed}: illegal #{inspect(event)} on #{inspect(current)}")
      end

    Map.put(seats, seat, next)
  end
end
