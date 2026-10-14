defmodule SeatReservation do
  @moduledoc """
  Public API of the seat reservation server. This is the contract `load_test.exs` uses.

  Keep these function names and return values. How you implement them — which
  processes exist, who owns the state, how failures are handled — is up to you.

  There are #{100} seats, numbered 1..100.

  ## Guarantees

    * Input is validated here, in the caller's process, so malformed input
      never reaches the server.
    * A fan acts only for itself: `fan` must be the calling process.
      `hold/2` and `confirm/2` return `{:error, :invalid}` otherwise, and
      `release/2` does nothing.
    * A held seat is freed when its fan process exits. A confirmed seat stays
      confirmed.
    * Seat state survives a crash of the server process.
  """

  alias SeatReservation.Server

  @seat_count 100
  @hold_timeout_ms 10_000

  @type seat :: 1..100
  @type fan :: pid()
  @type seat_state :: :free | {:held, fan} | {:confirmed, fan}

  def seat_count, do: @seat_count
  def hold_timeout_ms, do: @hold_timeout_ms

  @doc "Returns `true` if `term` is a valid seat number. Allowed in guards."
  defguard is_seat(term) when is_integer(term) and term >= 1 and term <= @seat_count

  @doc """
  Hold a seat for the given fan. Only one fan can hold a seat at a time.
  A hold expires automatically after #{@hold_timeout_ms} ms unless confirmed.

  Returns `:ok` or `{:error, :taken}`. Invalid input must return `{:error, :invalid}`,
  not crash the server.

  Holding a seat the fan already holds returns `:ok` and does not extend the hold.
  """
  @spec hold(seat, fan) :: :ok | {:error, :taken | :invalid}
  def hold(seat, fan) when is_seat(seat) and is_pid(fan), do: Server.hold(Server, seat, fan)
  def hold(_seat, _fan), do: {:error, :invalid}

  @doc """
  Confirm a seat currently held by this fan.
  Returns `:ok` or `{:error, :not_held}`.

  Confirming a seat the fan has already confirmed returns `:ok`.
  """
  @spec confirm(seat, fan) :: :ok | {:error, :not_held | :invalid}
  def confirm(seat, fan) when is_seat(seat) and is_pid(fan), do: Server.confirm(Server, seat, fan)
  def confirm(_seat, _fan), do: {:error, :invalid}

  @doc """
  Release a seat held or confirmed by this fan. Always returns `:ok`.
  """
  @spec release(seat, fan) :: :ok
  def release(seat, fan) when is_seat(seat) and is_pid(fan), do: Server.release(Server, seat, fan)
  def release(_seat, _fan), do: :ok

  @doc """
  Subscribe the calling process to seat events. After subscribing, the caller
  receives messages of the form:

      {:seat_event, seat, :held | :released | :confirmed, fan}

  Subscribing twice has no effect. The subscription ends when the caller exits.

  To build a consistent view, subscribe first and then call `seats/0`. Applying
  the events received afterwards, in order, to that snapshot always yields the
  current state.
  """
  @spec subscribe() :: :ok
  def subscribe, do: Server.subscribe(Server)

  @doc """
  Snapshot of all seats: `%{seat => :free | {:held, fan} | {:confirmed, fan}}`.
  """
  @spec seats() :: %{seat => seat_state}
  def seats, do: Server.seats(Server)
end
