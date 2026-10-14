defmodule SeatReservationTest do
  # Uses the application's server, which other test modules share.
  use ExUnit.Case, async: false

  describe "input validation" do
    test "malformed input returns an error without reaching the server" do
      for seat <- [0, 101, -5, 1.0, :banana, "1", nil] do
        assert SeatReservation.hold(seat, self()) == {:error, :invalid}
        assert SeatReservation.confirm(seat, self()) == {:error, :invalid}
        assert SeatReservation.release(seat, self()) == :ok
      end

      for fan <- [:not_a_pid, nil, make_ref(), "fan"] do
        assert SeatReservation.hold(1, fan) == {:error, :invalid}
        assert SeatReservation.confirm(1, fan) == {:error, :invalid}
        assert SeatReservation.release(1, fan) == :ok
      end
    end

    test "is_seat/1 accepts exactly 1..100" do
      require SeatReservation

      assert Enum.all?(1..100, &SeatReservation.is_seat/1)
      refute Enum.any?([0, 101, 1.0, :a, nil], &SeatReservation.is_seat/1)
    end
  end

  describe "the application's server" do
    test "hold, confirm and release a seat, with events" do
      :ok = SeatReservation.subscribe()
      seat = free_seat()
      me = self()

      assert SeatReservation.hold(seat, me) == :ok
      assert_receive {:seat_event, ^seat, :held, ^me}
      assert SeatReservation.seats()[seat] == {:held, me}

      assert SeatReservation.confirm(seat, me) == :ok
      assert_receive {:seat_event, ^seat, :confirmed, ^me}

      assert SeatReservation.release(seat, me) == :ok
      assert_receive {:seat_event, ^seat, :released, ^me}
      assert SeatReservation.seats()[seat] == :free
    end

    test "a process cannot hold a seat for another fan" do
      other = spawn(fn -> Process.sleep(:infinity) end)
      seat = free_seat()

      assert SeatReservation.hold(seat, other) == {:error, :invalid}
      assert SeatReservation.seats()[seat] == :free
      Process.exit(other, :kill)
    end

    test "seats/0 returns every seat in its public shape" do
      seats = SeatReservation.seats()

      assert Map.keys(seats) |> Enum.sort() == Enum.to_list(1..100)
      assert Enum.all?(Map.values(seats), &public_state?/1)
    end
  end

  defp public_state?(:free), do: true
  defp public_state?({:held, fan}), do: is_pid(fan)
  defp public_state?({:confirmed, fan}), do: is_pid(fan)
  defp public_state?(_other), do: false

  defp free_seat do
    Enum.find_value(SeatReservation.seats(), fn {seat, state} -> state == :free && seat end)
  end
end
