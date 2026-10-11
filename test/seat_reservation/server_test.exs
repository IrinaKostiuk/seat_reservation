defmodule SeatReservation.ServerTest do
  use SeatReservation.ServerCase, async: true

  import ExUnit.CaptureLog

  setup do
    %{a: TestFan.start(), b: TestFan.start()}
  end

  describe "hold" do
    test "holds a free seat and notifies subscribers", %{server: server, a: a} do
      assert TestFan.hold(a, server, 1) == :ok
      assert_receive {:seat_event, 1, :held, ^a}
      assert Server.seats(server)[1] == {:held, a}
    end

    test "rejects a seat held or confirmed by another fan", %{server: server, a: a, b: b} do
      :ok = TestFan.hold(a, server, 1)
      assert TestFan.hold(b, server, 1) == {:error, :taken}

      :ok = TestFan.confirm(a, server, 1)
      assert TestFan.hold(b, server, 1) == {:error, :taken}
      assert Server.seats(server)[1] == {:confirmed, a}
    end

    @tag hold_timeout_ms: 200
    test "holding your own seat again is ok but does not extend the hold", %{server: server, a: a} do
      started = System.monotonic_time(:millisecond)
      :ok = TestFan.hold(a, server, 1)
      Process.sleep(120)
      assert TestFan.hold(a, server, 1) == :ok

      assert_receive {:seat_event, 1, :released, ^a}, 500
      assert System.monotonic_time(:millisecond) - started < 300
    end
  end

  describe "confirm" do
    @tag hold_timeout_ms: 100
    test "confirms the fan's own hold, which then never expires", %{server: server, a: a} do
      :ok = TestFan.hold(a, server, 1)
      assert TestFan.confirm(a, server, 1) == :ok
      assert_receive {:seat_event, 1, :confirmed, ^a}

      refute_receive {:seat_event, 1, :released, _fan}, 250
      assert Server.seats(server)[1] == {:confirmed, a}
    end

    test "confirming twice is ok and notifies once", %{server: server, a: a} do
      :ok = TestFan.hold(a, server, 1)
      :ok = TestFan.confirm(a, server, 1)
      assert TestFan.confirm(a, server, 1) == :ok

      assert_receive {:seat_event, 1, :confirmed, ^a}
      refute_receive {:seat_event, 1, :confirmed, ^a}
    end

    test "fails for a free seat or someone else's hold", %{server: server, a: a, b: b} do
      assert TestFan.confirm(a, server, 1) == {:error, :not_held}

      :ok = TestFan.hold(a, server, 1)
      assert TestFan.confirm(b, server, 1) == {:error, :not_held}
    end
  end

  describe "release" do
    test "frees a held or confirmed seat and notifies subscribers", %{server: server, a: a} do
      :ok = TestFan.hold(a, server, 1)
      assert TestFan.release(a, server, 1) == :ok
      assert_receive {:seat_event, 1, :released, ^a}
      assert Server.seats(server)[1] == :free

      :ok = TestFan.hold(a, server, 2)
      :ok = TestFan.confirm(a, server, 2)
      assert TestFan.release(a, server, 2) == :ok
      assert_receive {:seat_event, 2, :released, ^a}
      assert Server.seats(server)[2] == :free
    end

    test "does nothing for someone else's seat", %{server: server, a: a, b: b} do
      :ok = TestFan.hold(a, server, 1)
      assert TestFan.release(b, server, 1) == :ok

      refute_receive {:seat_event, 1, :released, _fan}
      assert Server.seats(server)[1] == {:held, a}
    end
  end

  describe "identity" do
    test "a process cannot act on behalf of another fan", %{server: server, a: a} do
      assert Server.hold(server, 1, a) == {:error, :invalid}

      :ok = TestFan.hold(a, server, 1)
      assert Server.confirm(server, 1, a) == {:error, :invalid}
      assert Server.release(server, 1, a) == :ok
      assert Server.seats(server)[1] == {:held, a}
    end
  end

  describe "expiry" do
    @tag hold_timeout_ms: 100
    test "frees an unconfirmed hold after the timeout", %{server: server, a: a} do
      :ok = TestFan.hold(a, server, 1)
      assert_receive {:seat_event, 1, :released, ^a}, 500
      assert Server.seats(server)[1] == :free
    end

    @tag hold_timeout_ms: 100
    test "a confirm that arrives after the expiry fails", %{server: server, a: a} do
      :ok = TestFan.hold(a, server, 1)
      assert_receive {:seat_event, 1, :released, ^a}, 500
      assert TestFan.confirm(a, server, 1) == {:error, :not_held}
    end

    test "an expiry that arrives after the confirm is ignored", %{server: server, a: a} do
      :ok = TestFan.hold(a, server, 1)
      ref = hold_ref(server, 1)
      :ok = TestFan.confirm(a, server, 1)

      send(Process.whereis(server), {:expire, 1, ref})
      assert Server.seats(server)[1] == {:confirmed, a}
    end

    test "a timer from an earlier hold cannot free a newer hold", %{server: server, a: a, b: b} do
      :ok = TestFan.hold(a, server, 1)
      old_ref = hold_ref(server, 1)
      :ok = TestFan.release(a, server, 1)
      :ok = TestFan.hold(b, server, 1)

      send(Process.whereis(server), {:expire, 1, old_ref})
      assert Server.seats(server)[1] == {:held, b}
    end
  end

  describe "fan exits" do
    test "a fan's held seat is freed when it dies", %{server: server, a: a} do
      :ok = TestFan.hold(a, server, 1)
      Process.exit(a, :kill)

      assert_receive {:seat_event, 1, :released, ^a}
      assert Server.seats(server)[1] == :free
    end

    test "a fan's confirmed seat stays confirmed when it dies", %{server: server, a: a} do
      :ok = TestFan.hold(a, server, 1)
      :ok = TestFan.confirm(a, server, 1)
      Process.exit(a, :kill)

      refute_receive {:seat_event, 1, :released, _fan}
      assert Server.seats(server)[1] == {:confirmed, a}
    end

    test "a :DOWN from an earlier hold cannot free a newer hold", %{server: server, a: a, b: b} do
      :ok = TestFan.hold(a, server, 1)
      old_ref = hold_ref(server, 1)
      :ok = TestFan.release(a, server, 1)
      :ok = TestFan.hold(b, server, 1)

      send(Process.whereis(server), {:DOWN, old_ref, :process, a, :killed})
      assert Server.seats(server)[1] == {:held, b}
    end

    test "expiry and death of the same hold release the seat once", %{server: server, a: a} do
      :ok = TestFan.hold(a, server, 1)
      ref = hold_ref(server, 1)
      Process.exit(a, :kill)
      assert_receive {:seat_event, 1, :released, ^a}

      send(Process.whereis(server), {:expire, 1, ref})
      refute_receive {:seat_event, 1, :released, ^a}, 200
    end

    test "a fan that dies before its hold is processed does not keep the seat", %{server: server} do
      pid = Process.whereis(server)
      :sys.suspend(pid)
      fan = spawn(fn -> Server.hold(server, 1, self()) end)
      eventually(fn -> Process.info(pid, :message_queue_len) == {:message_queue_len, 1} end)
      Process.exit(fan, :kill)
      :sys.resume(pid)

      assert_receive {:seat_event, 1, :held, ^fan}
      assert_receive {:seat_event, 1, :released, ^fan}
      assert Server.seats(server)[1] == :free
    end
  end

  describe "subscribers" do
    test "subscribing twice delivers each event once", %{server: server, a: a} do
      assert Server.subscribe(server) == :ok
      :ok = TestFan.hold(a, server, 1)

      assert_receive {:seat_event, 1, :held, ^a}
      refute_receive {:seat_event, 1, :held, ^a}
      assert_consistent(server)
    end

    test "a subscriber that dies is removed", %{server: server, a: a} do
      :ok = TestFan.subscribe(a, server)
      assert Map.has_key?(:sys.get_state(server).subscribers, a)

      Process.exit(a, :kill)
      eventually(fn -> not Map.has_key?(:sys.get_state(server).subscribers, a) end)
      assert_consistent(server)
    end
  end

  describe "garbage" do
    test "malformed requests and messages leave the server and its data intact",
         %{server: server, a: a} do
      :ok = TestFan.hold(a, server, 1)
      pid = Process.whereis(server)
      before = Server.seats(server)

      log =
        capture_log(fn ->
          assert GenServer.call(server, :junk) == {:error, :invalid}
          assert GenServer.call(server, {:hold, 0, self()}) == {:error, :invalid}
          assert GenServer.call(server, {:hold, :banana, self()}) == {:error, :invalid}
          assert GenServer.call(server, {:hold, 2, :not_a_pid}) == {:error, :invalid}
          assert GenServer.call(server, {:confirm, 101, self()}) == {:error, :invalid}
          assert GenServer.call(server, {:release, -5, self()}) == :ok
          GenServer.cast(server, {:hold, 2, self()})
          send(pid, :junk)
          send(pid, {:expire, :banana, make_ref()})
          send(pid, {:expire, 1, make_ref()})
          send(pid, {:DOWN, make_ref(), :process, a, :forged})
          assert Server.seats(server) == before
        end)

      assert log =~ "ignored call: :junk"
      assert log =~ "ignored cast"
      assert log =~ "ignored message: :junk"
      assert Process.whereis(server) == pid
      assert_consistent(server)
    end
  end

  describe "server crash" do
    test "held and confirmed seats survive", %{server: server, a: a, b: b} do
      :ok = TestFan.hold(a, server, 1)
      :ok = TestFan.hold(b, server, 2)
      :ok = TestFan.confirm(b, server, 2)
      before = Server.seats(server)

      crash_server(server)

      assert Server.seats(server) == before
      assert TestFan.confirm(a, server, 1) == :ok
      assert_consistent(server)
    end

    @tag hold_timeout_ms: 300
    test "a held seat still expires at its original deadline", %{server: server, a: a} do
      started = System.monotonic_time(:millisecond)
      :ok = TestFan.hold(a, server, 1)
      Process.sleep(100)

      crash_server(server)
      assert Server.seats(server)[1] == {:held, a}

      assert_receive {:seat_event, 1, :released, ^a}, 1_000
      elapsed = System.monotonic_time(:millisecond) - started
      assert elapsed >= 300 and elapsed < 450, "released after #{elapsed} ms"
    end

    test "a fan that died while the server was down loses its hold", %{server: server, a: a} do
      :ok = TestFan.hold(a, server, 1)
      # Suspended, the server cannot handle the :DOWN before it is killed,
      # so only the restored server can free the seat.
      :sys.suspend(server)
      Process.exit(a, :kill)
      crash_server(server)

      assert_receive {:seat_event, 1, :released, ^a}
      assert Server.seats(server)[1] == :free
    end

    test "subscribers keep receiving events", %{server: server, a: a} do
      crash_server(server)
      :ok = TestFan.hold(a, server, 1)
      assert_receive {:seat_event, 1, :held, ^a}
    end

    test "invalid rows are reset instead of crashing the server" do
      store = Module.concat(__MODULE__, "Store#{System.unique_integer([:positive])}")
      start_supervised!({Store, name: store}, id: :corrupt_store)
      {:ok, table} = Store.claim(store)

      :ets.insert(table, [
        {5, :bogus},
        {7, {:held, :not_a_pid, 0}},
        {8, {:confirmed, self()}},
        {:junk, 1},
        {{:subscriber, :not_a_pid}, true}
      ])

      :ets.give_away(table, Process.whereis(store), :returned)
      server = Module.concat(store, Server)

      log =
        capture_log(fn ->
          start_supervised!({Server, name: server, store: store, hold_timeout_ms: 100},
            id: :corrupt_server
          )
        end)

      seats = Server.seats(server)
      assert map_size(seats) == 100
      assert seats[5] == :free
      assert seats[7] == :free
      assert seats[8] == {:confirmed, self()}
      assert log =~ "reset seat 5"
      assert log =~ "dropped invalid row"
      assert_consistent(server)
    end
  end

  describe "load" do
    test "1,000 fans racing for 100 seats: exactly one winner per seat", %{server: server} do
      results = burst(server, 1_000)

      winners = for {pid, seat, :ok} <- results, do: {seat, pid}
      assert length(results) == 1_000
      assert length(winners) == 100
      assert winners |> Enum.map(&elem(&1, 0)) |> Enum.uniq() |> length() == 100

      seats = Server.seats(server)
      assert Enum.all?(winners, fn {seat, pid} -> seats[seat] == {:held, pid} end)
    end

    test "stays responsive with 1,000 subscribers during a 1,000-fan burst", %{server: server} do
      for _ <- 1..1_000, do: :ok = TestFan.subscribe(TestFan.start(), server)

      started = System.monotonic_time(:millisecond)
      results = burst(server, 1_000)
      elapsed = System.monotonic_time(:millisecond) - started

      assert length(results) == 1_000
      assert elapsed < 1_000, "burst took #{elapsed} ms"
    end
  end

  # Starts `count` fans that each try to hold one seat at the same moment.
  # They stay alive until the test ends. Returns `[{fan, seat, result}]`.
  defp burst(server, count) do
    test = self()

    fans =
      for i <- 1..count do
        spawn(fn ->
          owner = Process.monitor(test)
          seat = rem(i, 100) + 1

          receive do
            :go -> send(test, {:result, self(), seat, Server.hold(server, seat, self())})
          end

          receive do
            {:DOWN, ^owner, :process, _pid, _reason} -> :ok
          end
        end)
      end

    Enum.each(fans, &send(&1, :go))

    Enum.map(fans, fn _fan ->
      receive do
        {:result, pid, seat, result} -> {pid, seat, result}
      end
    end)
  end
end
