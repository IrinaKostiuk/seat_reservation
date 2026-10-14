defmodule SeatReservation.ServerCase do
  @moduledoc """
  Test case for the core. Every test gets its own seat tree (store and server)
  under unique names, so tests run concurrently, and the test process is
  subscribed to its events. Tests about expiry set a short hold timeout with
  the `hold_timeout_ms: n` tag (default 5 s).
  """
  use ExUnit.CaseTemplate

  import ExUnit.Assertions

  alias SeatReservation.Server

  using do
    quote do
      import SeatReservation.ServerCase

      alias SeatReservation.{Server, Store, TestFan}
    end
  end

  setup context do
    name = Module.concat(context.module, "T#{System.unique_integer([:positive])}")
    timeout = Map.get(context, :hold_timeout_ms, 5_000)
    start_supervised!({SeatReservation.Supervisor, name: name, hold_timeout_ms: timeout})
    server = SeatReservation.Supervisor.server_name(name)
    :ok = Server.subscribe(server)
    %{server: server}
  end

  @doc "Kills the server and waits until the supervisor has restarted it."
  def crash_server(server) do
    old = Process.whereis(server)
    Process.exit(old, :kill)
    eventually(fn -> Process.whereis(server) not in [nil, old] end)
    # Any call waits until the restarted server has finished restoring.
    _ = Server.seats(server)
    :ok
  end

  @doc "The monitor reference identifying the current hold on `seat`."
  def hold_ref(server, seat), do: :sys.get_state(server).holds[seat].ref

  @doc "Retries `fun` every 10 ms until it returns a truthy value, failing after ~2 s."
  def eventually(fun, attempts \\ 200)
  def eventually(_fun, 0), do: flunk("condition not met in time")

  def eventually(fun, attempts) do
    with falsy when falsy in [nil, false] <- fun.() do
      Process.sleep(10)
      eventually(fun, attempts - 1)
    end
  end

  @doc """
  Asserts that the server's in-memory indexes agree with its table. The state
  and the table are captured atomically inside the server process.
  """
  def assert_consistent(server) do
    {state, rows} = snapshot(server)
    seat_rows = for {seat, value} <- rows, is_integer(seat), into: %{}, do: {seat, value}
    subscriber_rows = for {{:subscriber, pid}, true} <- rows, do: pid

    assert Map.keys(seat_rows) |> Enum.sort() == Enum.to_list(1..100)
    assert length(rows) == 100 + length(subscriber_rows), "unexpected rows: #{inspect(rows)}"
    assert Enum.all?(seat_rows, fn {_seat, value} -> valid_value?(value) end)

    held = for {seat, {:held, _fan, _deadline}} <- seat_rows, do: seat
    assert Enum.sort(held) == state.holds |> Map.keys() |> Enum.sort()

    assert Enum.all?(state.holds, fn {seat, %{ref: ref}} ->
             state.monitors[ref] == {:hold, seat}
           end)

    assert Enum.sort(subscriber_rows) == state.subscribers |> Map.keys() |> Enum.sort()

    assert Enum.all?(state.subscribers, fn {pid, ref} ->
             state.monitors[ref] == {:subscriber, pid}
           end)

    assert map_size(state.monitors) == map_size(state.holds) + map_size(state.subscribers)
  end

  defp snapshot(server) do
    caller = self()
    ref = make_ref()

    :sys.replace_state(server, fn state ->
      send(caller, {ref, state, :ets.tab2list(state.table)})
      state
    end)

    receive do
      {^ref, state, rows} -> {state, rows}
    end
  end

  defp valid_value?(:free), do: true
  defp valid_value?({:held, fan, deadline}), do: is_pid(fan) and is_integer(deadline)
  defp valid_value?({:confirmed, fan}), do: is_pid(fan)
  defp valid_value?(_value), do: false
end
