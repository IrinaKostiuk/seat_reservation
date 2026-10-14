defmodule SeatReservation do
  @moduledoc """
  Public API of the seat reservation server. This is the contract `load_test.exs` uses.

  Keep these function names and return values. How you implement them — which
  processes exist, who owns the state, how failures are handled — is up to you.

  There are #{100} seats, numbered 1..100.
  """

  @seat_count 100
  @hold_timeout_ms 10_000
  @table_name :seat_reservation_seats
  @pubsub SeatReservation.Subscribers
  @event_topic "events"

  @type seat :: 1..100
  @type fan :: pid()
  @type seat_state :: :free | {:held, fan} | {:confirmed, fan}

  def seat_count, do: @seat_count
  def hold_timeout_ms, do: @hold_timeout_ms

  @doc """
  Hold a seat for the given fan. Only one fan can hold a seat at a time.
  A hold expires automatically after #{@hold_timeout_ms} ms unless confirmed.

  Returns `:ok` or `{:error, :taken}`. Invalid input must return `{:error, :invalid}`,
  not crash the server.
  """
  @spec hold(seat, fan) :: :ok | {:error, :taken | :invalid}
  def hold(seat, fan) when is_integer(seat) and seat in 1..@seat_count and is_pid(fan) do
    SeatReservation.Seat.hold(seat, fan)
  rescue
    _ -> {:error, :invalid}
  catch
    :exit, _ -> {:error, :invalid}
  end

  def hold(_seat, _fan), do: {:error, :invalid}

  @doc """
  Confirm a seat currently held by this fan.
  Returns `:ok` or `{:error, :not_held}`.
  """
  @spec confirm(seat, fan) :: :ok | {:error, :not_held | :invalid}
  def confirm(seat, fan) when is_integer(seat) and seat in 1..@seat_count and is_pid(fan) do
    SeatReservation.Seat.confirm(seat, fan)
  rescue
    _ -> {:error, :invalid}
  catch
    :exit, _ -> {:error, :invalid}
  end

  def confirm(_seat, _fan), do: {:error, :invalid}

  @doc """
  Release a seat held or confirmed by this fan. Always returns `:ok`.
  """
  @spec release(seat, fan) :: :ok
  def release(seat, fan) when is_integer(seat) and seat in 1..@seat_count and is_pid(fan) do
    SeatReservation.Seat.release(seat, fan)
  rescue
    _ -> :ok
  catch
    :exit, _ -> :ok
  end

  def release(_seat, _fan), do: :ok

  @doc """
  Subscribe the calling process to seat events. After subscribing, the caller
  receives messages of the form:

      {:seat_event, seat, :held | :released | :confirmed, fan}
  """
  @spec subscribe() :: :ok
  def subscribe do
    caller = self()

    if @event_topic not in Registry.keys(@pubsub, caller) do
      Registry.register(@pubsub, @event_topic, [])
    end

    :ok
  rescue
    _ -> :ok
  catch
    :exit, _ -> :ok
  end

  @doc """
  Snapshot of all seats: `%{seat => :free | {:held, fan} | {:confirmed, fan}}`.
  """
  @spec seats() :: %{seat => seat_state}
  def seats do
    @table_name
    |> :ets.tab2list()
    |> Map.new()
  rescue
    _ -> %{}
  end
end
