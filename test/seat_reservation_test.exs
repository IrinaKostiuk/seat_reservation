defmodule SeatReservationTest do
  use ExUnit.Case, async: false

  setup do
    # Ensure all seats are released before each test
    for {seat, state} <- SeatReservation.seats() do
      case state do
        {:held, fan} -> SeatReservation.release(seat, fan)
        {:confirmed, fan} -> SeatReservation.release(seat, fan)
        :free -> :ok
      end
    end

    :ok
  end

  test "returns correct seat count and hold timeout" do
    assert SeatReservation.seat_count() == 100
    assert SeatReservation.hold_timeout_ms() == 10_000
  end

  test "initial seats map contains 100 free seats" do
    seats = SeatReservation.seats()
    assert map_size(seats) == 100
    assert Enum.all?(1..100, fn s -> Map.get(seats, s) == :free end)
  end

  test "fan can hold, confirm, and release a seat" do
    fan = self()
    assert SeatReservation.hold(1, fan) == :ok
    assert Map.get(SeatReservation.seats(), 1) == {:held, fan}

    assert SeatReservation.confirm(1, fan) == :ok
    assert Map.get(SeatReservation.seats(), 1) == {:confirmed, fan}

    assert SeatReservation.release(1, fan) == :ok
    assert Map.get(SeatReservation.seats(), 1) == :free
  end

  test "cannot hold an already held or confirmed seat" do
    fan1 = self()
    fan2 = spawn(fn -> Process.sleep(1000) end)

    assert SeatReservation.hold(2, fan1) == :ok
    assert SeatReservation.hold(2, fan2) == {:error, :taken}

    assert SeatReservation.confirm(2, fan1) == :ok
    assert SeatReservation.hold(2, fan2) == {:error, :taken}

    SeatReservation.release(2, fan1)
  end

  test "confirming unheld seat or seat held by another fan returns error" do
    fan1 = self()
    fan2 = spawn(fn -> Process.sleep(1000) end)

    assert SeatReservation.confirm(3, fan1) == {:error, :not_held}

    assert SeatReservation.hold(3, fan1) == :ok
    assert SeatReservation.confirm(3, fan2) == {:error, :not_held}

    SeatReservation.release(3, fan1)
  end

  test "releasing seat held by another fan does not affect it" do
    fan1 = self()
    fan2 = spawn(fn -> Process.sleep(1000) end)

    assert SeatReservation.hold(4, fan1) == :ok
    assert SeatReservation.release(4, fan2) == :ok
    assert Map.get(SeatReservation.seats(), 4) == {:held, fan1}

    SeatReservation.release(4, fan1)
  end

  test "invalid arguments return error or ok and do not crash" do
    assert SeatReservation.hold(:invalid, self()) == {:error, :invalid}
    assert SeatReservation.hold(0, self()) == {:error, :invalid}
    assert SeatReservation.hold(101, self()) == {:error, :invalid}
    assert SeatReservation.hold(1, :not_a_pid) == {:error, :invalid}

    assert SeatReservation.confirm(:invalid, self()) == {:error, :invalid}
    assert SeatReservation.confirm(0, self()) == {:error, :invalid}
    assert SeatReservation.confirm(101, self()) == {:error, :invalid}
    assert SeatReservation.confirm(1, :not_a_pid) == {:error, :invalid}

    assert SeatReservation.release(:invalid, self()) == :ok
    assert SeatReservation.release(-1, self()) == :ok
    assert SeatReservation.release(1, :not_a_pid) == :ok
  end

  test "subscriber receives event notifications" do
    assert SeatReservation.subscribe() == :ok
    fan = self()

    SeatReservation.hold(5, fan)
    assert_receive {:seat_event, 5, :held, ^fan}

    SeatReservation.confirm(5, fan)
    assert_receive {:seat_event, 5, :confirmed, ^fan}

    SeatReservation.release(5, fan)
    assert_receive {:seat_event, 5, :released, ^fan}
  end

  test "crashing fan holding seat automatically releases the seat" do
    SeatReservation.subscribe()

    fan =
      spawn(fn ->
        receive do
          :hold -> SeatReservation.hold(6, self())
        end

        # stay alive until killed
        receive do
          :die -> :ok
        end
      end)

    send(fan, :hold)
    assert_receive {:seat_event, 6, :held, ^fan}
    assert Map.get(SeatReservation.seats(), 6) == {:held, fan}

    Process.exit(fan, :kill)
    assert_receive {:seat_event, 6, :released, ^fan}
    assert Map.get(SeatReservation.seats(), 6) == :free
  end
end
