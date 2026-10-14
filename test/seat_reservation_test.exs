defmodule SeatReservationTest do
  use ExUnit.Case, async: false

  alias SeatReservation, as: Seats
  alias SeatReservation.Server

  setup do
    # Every test exercises the real supervised, registered public API.
    :ok = Supervisor.terminate_child(SeatReservation.Supervisor, Server)
    {:ok, _pid} = Supervisor.restart_child(SeatReservation.Supervisor, Server)
    :ok
  end

  test "all 100 seats start free and ownership controls transitions" do
    fan = self()
    other = fan_process()
    assert Seats.seats() == Map.new(1..100, &{&1, :free})
    assert :ok = Seats.hold(1, fan)
    assert {:error, :taken} = Seats.hold(1, fan)
    assert {:error, :taken} = Seats.hold(1, other)
    assert {:error, :not_held} = Seats.confirm(1, other)
    assert :ok = Seats.release(1, other)
    assert Seats.seats()[1] == {:held, fan}
    assert :ok = Seats.confirm(1, fan)
    assert {:error, :not_held} = Seats.confirm(1, fan)
    assert {:error, :taken} = Seats.hold(1, other)
    assert :ok = Seats.release(1, other)
    assert Seats.seats()[1] == {:confirmed, fan}
    assert :ok = Seats.release(1, fan)
    assert :ok = Seats.release(1, fan)
    assert {:error, :not_held} = Seats.confirm(1, fan)
    assert Seats.seats()[1] == :free
  end

  test "invalid input and unexpected messages preserve seat data and server identity" do
    server = Process.whereis(Server)
    assert :ok = Seats.hold(1, self())
    before = Seats.seats()

    for seat <- [:banana, 0, 101, -1, 1.0, nil, [], %{}] do
      assert {:error, :invalid} = Seats.hold(seat, self())
      assert {:error, :invalid} = Seats.confirm(seat, self())
      assert :ok = Seats.release(seat, self())
    end

    for fan <- [:not_a_pid, nil, 1, [], %{}] do
      assert {:error, :invalid} = Seats.hold(1, fan)
      assert {:error, :invalid} = Seats.confirm(1, fan)
      assert :ok = Seats.release(1, fan)
    end

    send(server, :garbage)
    send(server, {:expire, 1, make_ref()})
    send(server, {:DOWN, make_ref(), :process, self(), :fake})
    GenServer.cast(server, {:hold, 2, self()})
    assert {:error, :invalid} = GenServer.call(server, {:unexpected, :request})
    assert Seats.seats() == before
    assert Process.whereis(Server) == server
  end

  test "1,000 concurrent callers competing for one seat produce one winner" do
    parent = self()

    results =
      1..1_000
      |> Task.async_stream(fn _ -> Seats.hold(1, parent) end,
        max_concurrency: 1_000,
        ordered: false
      )
      |> Enum.map(fn {:ok, result} -> result end)

    assert Enum.count(results, &(&1 == :ok)) == 1
    assert Enum.count(results, &(&1 == {:error, :taken})) == 999
    assert Seats.seats()[1] == {:held, parent}
  end

  test "subscriptions are deduplicated and events describe only actual changes" do
    fan = self()
    other = fan_process()
    assert :ok = Seats.subscribe()
    assert :ok = Seats.subscribe()
    assert :ok = Seats.hold(1, fan)
    assert {:error, :taken} = Seats.hold(1, other)
    assert {:error, :not_held} = Seats.confirm(1, other)
    assert :ok = Seats.release(1, other)
    assert :ok = Seats.confirm(1, fan)
    assert :ok = Seats.release(1, fan)
    assert :ok = Seats.release(1, fan)
    assert_receive {:seat_event, 1, :held, ^fan}
    assert_receive {:seat_event, 1, :confirmed, ^fan}
    assert_receive {:seat_event, 1, :released, ^fan}
    refute_receive {:seat_event, _, _, _}
  end

  test "fan death releases all active holds, preserves confirmations and isolates other fans" do
    fan = fan_process()
    other = fan_process()
    server = Process.whereis(Server)
    :ok = Seats.subscribe()
    for seat <- 1..3, do: assert(:ok = Seats.hold(seat, fan))
    assert :ok = Seats.confirm(3, fan)
    assert :ok = Seats.hold(4, other)
    Process.exit(fan, :kill)
    assert_receive {:seat_event, 1, :released, ^fan}, 1_000
    assert_receive {:seat_event, 2, :released, ^fan}, 1_000
    assert Seats.seats()[1] == :free
    assert Seats.seats()[2] == :free
    assert Seats.seats()[3] == {:confirmed, fan}
    assert Seats.seats()[4] == {:held, other}
    assert Process.alive?(other)
    assert Process.whereis(Server) == server
    refute Map.has_key?(:sys.get_state(Server).fans, fan)
  end

  test "dead subscribers and unused hold monitors are removed" do
    parent = self()

    subscriber =
      spawn(fn ->
        :ok = Seats.subscribe()
        send(parent, :subscribed)
        receive do: (:stop -> :ok)
      end)

    on_exit(fn -> Process.exit(subscriber, :kill) end)
    assert_receive :subscribed
    assert Map.has_key?(:sys.get_state(Server).subscribers, subscriber)
    Process.exit(subscriber, :kill)
    eventually(fn -> not Map.has_key?(:sys.get_state(Server).subscribers, subscriber) end)
    assert :ok = Seats.hold(1, self())
    assert :ok = Seats.hold(2, self())
    assert :ok = Seats.release(1, self())
    assert Map.has_key?(:sys.get_state(Server).fans, self())
    assert :ok = Seats.confirm(2, self())
    assert :sys.get_state(Server).fans == %{}
  end

  test "stale timers cannot release a newer hold or a confirmed reservation" do
    fan = self()
    :ok = Seats.hold(1, fan)
    old_token = :sys.get_state(Server).holds[1].token
    :ok = Seats.release(1, fan)
    :ok = Seats.hold(1, fan)
    send(Server, {:expire, 1, old_token})
    assert Seats.seats()[1] == {:held, fan}
    current_token = :sys.get_state(Server).holds[1].token
    :ok = Seats.confirm(1, fan)
    send(Server, {:expire, 1, current_token})
    assert Seats.seats()[1] == {:confirmed, fan}
  end

  test "calls enforce elapsed deadlines even before the timer is delivered" do
    fan = self()
    :ok = Seats.subscribe()
    for seat <- 1..3, do: :ok = Seats.hold(seat, fan)

    # Model timer delivery lag without waiting for scheduler timing in this test.
    :sys.replace_state(Server, fn state ->
      past = System.monotonic_time(:millisecond) - 1

      %{
        state
        | holds: Map.new(state.holds, fn {seat, hold} -> {seat, %{hold | deadline: past}} end)
      }
    end)

    assert {:error, :not_held} = Seats.confirm(1, fan)
    assert :ok = Seats.hold(2, fan)
    assert Seats.seats()[3] == :free
    for seat <- 1..3, do: assert_receive({:seat_event, ^seat, :released, ^fan})
    assert Seats.seats()[2] == {:held, fan}
  end

  @tag timeout: 15_000
  test "real timers expire holds after ten seconds while confirmations survive" do
    fan = self()
    assert Seats.hold_timeout_ms() == 10_000
    :ok = Seats.subscribe()
    started = System.monotonic_time(:millisecond)
    :ok = Seats.hold(1, fan)
    :ok = Seats.hold(2, fan)
    :ok = Seats.confirm(2, fan)
    assert_receive {:seat_event, 1, :released, ^fan}, 11_000
    assert System.monotonic_time(:millisecond) - started >= 10_000
    assert Seats.seats()[1] == :free
    assert Seats.seats()[2] == {:confirmed, fan}
    refute_receive {:seat_event, _, :released, _}
  end

  defp fan_process do
    pid = spawn(fn -> receive do: (:stop -> :ok) end)
    on_exit(fn -> Process.exit(pid, :kill) end)
    pid
  end

  defp eventually(check, attempts \\ 100)
  defp eventually(check, 0), do: assert(check.())

  defp eventually(check, attempts) do
    unless check.() do
      Process.sleep(10)
      eventually(check, attempts - 1)
    end
  end
end
