defmodule SeatReservation.Server do
  @moduledoc """
  Owns every seat. All changes to all seats are serialized through this one
  process, which makes double booking impossible without locks.

  ## State

  The ETS table claimed from `SeatReservation.Store` is the source of truth and
  survives a crash of this process. Its rows are:

      {seat, :free}
      {seat, {:held, fan, deadline}}   # deadline: monotonic time in ms
      {seat, {:confirmed, fan}}
      {{:subscriber, pid}, true}

  Everything else in the struct (hold timers, process monitors and the
  subscriber map) is derived from the table and rebuilt by `init/1`, so a
  restarted server resumes where the crashed one stopped. Every change writes
  the table first and notifies subscribers second.

  ## Hold identity

  A hold is identified by the reference of the monitor on its fan. The expiry
  timer and the `:DOWN` message both carry it, so a message left over from an
  earlier hold of the same seat is recognised and ignored.
  """
  use GenServer

  import SeatReservation, only: [is_seat: 1]

  require Logger

  @enforce_keys [:table, :hold_timeout_ms]
  defstruct [:table, :hold_timeout_ms, holds: %{}, monitors: %{}, subscribers: %{}]

  @type seat :: SeatReservation.seat()
  @type fan :: SeatReservation.fan()

  @typep hold :: %{ref: reference(), timer: reference()}
  @typep t :: %__MODULE__{
           table: :ets.tid(),
           hold_timeout_ms: pos_integer(),
           holds: %{seat => hold},
           monitors: %{reference() => {:hold, seat} | {:subscriber, pid}},
           subscribers: %{pid => reference()}
         }

  ## Client

  @spec start_link(keyword) :: GenServer.on_start()
  def start_link(opts) do
    {name, opts} = Keyword.pop!(opts, :name)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @spec hold(GenServer.server(), seat, fan) :: :ok | {:error, :taken | :invalid}
  def hold(server, seat, fan), do: GenServer.call(server, {:hold, seat, fan})

  @spec confirm(GenServer.server(), seat, fan) :: :ok | {:error, :not_held | :invalid}
  def confirm(server, seat, fan), do: GenServer.call(server, {:confirm, seat, fan})

  @spec release(GenServer.server(), seat, fan) :: :ok
  def release(server, seat, fan), do: GenServer.call(server, {:release, seat, fan})

  @spec subscribe(GenServer.server()) :: :ok
  def subscribe(server), do: GenServer.call(server, :subscribe)

  @spec seats(GenServer.server()) :: %{seat => SeatReservation.seat_state()}
  def seats(server), do: GenServer.call(server, :seats)

  ## Callbacks

  @impl true
  def init(opts) do
    {:ok, table} = SeatReservation.Store.claim(Keyword.fetch!(opts, :store))
    state = %__MODULE__{table: table, hold_timeout_ms: Keyword.fetch!(opts, :hold_timeout_ms)}
    {:ok, restore(state)}
  end

  # Matching `fan` in both the request and `from` means these clauses only
  # run when the calling process is the fan it claims to be.
  @impl true
  def handle_call({:hold, seat, fan}, {fan, _tag}, state) when is_seat(seat) do
    case lookup(state, seat) do
      :free ->
        deadline = now() + state.hold_timeout_ms
        write(state, seat, {:held, fan, deadline})
        notify(state, seat, :held, fan)
        {:reply, :ok, track_hold(state, seat, fan, deadline)}

      {:held, ^fan, _deadline} ->
        {:reply, :ok, state}

      _taken ->
        {:reply, {:error, :taken}, state}
    end
  end

  def handle_call({:confirm, seat, fan}, {fan, _tag}, state) when is_seat(seat) do
    case lookup(state, seat) do
      {:held, ^fan, _deadline} ->
        write(state, seat, {:confirmed, fan})
        notify(state, seat, :confirmed, fan)
        {:reply, :ok, untrack_hold(state, seat)}

      {:confirmed, ^fan} ->
        {:reply, :ok, state}

      _other ->
        {:reply, {:error, :not_held}, state}
    end
  end

  def handle_call({:release, seat, fan}, {fan, _tag}, state) when is_seat(seat) do
    case lookup(state, seat) do
      {:held, ^fan, _deadline} -> {:reply, :ok, free_seat(state, seat, fan)}
      {:confirmed, ^fan} -> {:reply, :ok, free_seat(state, seat, fan)}
      _other -> {:reply, :ok, state}
    end
  end

  def handle_call(:subscribe, {pid, _tag}, state) do
    {:reply, :ok, add_subscriber(state, pid)}
  end

  def handle_call(:seats, _from, state) do
    seats = Map.new(1..SeatReservation.seat_count(), &{&1, public_state(lookup(state, &1))})
    {:reply, seats, state}
  end

  # Well-formed requests with an invalid seat, or sent on behalf of another fan.
  def handle_call({op, _seat, _fan}, _from, state) when op in [:hold, :confirm] do
    {:reply, {:error, :invalid}, state}
  end

  def handle_call({:release, _seat, _fan}, _from, state), do: {:reply, :ok, state}

  def handle_call(request, _from, state) do
    log_ignored("call", request)
    {:reply, {:error, :invalid}, state}
  end

  @impl true
  def handle_cast(request, state) do
    log_ignored("cast", request)
    {:noreply, state}
  end

  @impl true
  def handle_info({:expire, seat, ref}, state) do
    with %{^seat => %{ref: ^ref}} <- state.holds,
         {:held, fan, _deadline} <- lookup(state, seat) do
      {:noreply, free_seat(state, seat, fan)}
    else
      # Left over from a hold that was already released or confirmed.
      _stale -> {:noreply, state}
    end
  end

  def handle_info({:DOWN, ref, :process, pid, _reason}, state) do
    case Map.get(state.monitors, ref) do
      {:hold, seat} -> {:noreply, free_seat(state, seat, pid)}
      {:subscriber, subscriber} -> {:noreply, remove_subscriber(state, subscriber, ref)}
      # Left over from a hold that was already released or confirmed.
      nil -> {:noreply, state}
    end
  end

  def handle_info({:"ETS-TRANSFER", table, _from, _data}, %{table: table} = state) do
    {:noreply, state}
  end

  def handle_info(message, state) do
    log_ignored("message", message)
    {:noreply, state}
  end

  ## Holds

  @spec free_seat(t, seat, fan) :: t
  defp free_seat(state, seat, fan) do
    write(state, seat, :free)
    notify(state, seat, :released, fan)
    untrack_hold(state, seat)
  end

  @spec track_hold(t, seat, fan, integer) :: t
  defp track_hold(state, seat, fan, deadline) do
    ref = Process.monitor(fan)
    timer = Process.send_after(self(), {:expire, seat, ref}, deadline, abs: true)

    %{
      state
      | holds: Map.put(state.holds, seat, %{ref: ref, timer: timer}),
        monitors: Map.put(state.monitors, ref, {:hold, seat})
    }
  end

  # Neither demonitor's :flush option nor a synchronous cancel_timer is used:
  # both scan or wait on the mailbox, which is slow under a burst. A :DOWN or
  # :expire that is already queued is recognised as stale and ignored.
  @spec untrack_hold(t, seat) :: t
  defp untrack_hold(state, seat) do
    case Map.pop(state.holds, seat) do
      {nil, _holds} ->
        state

      {%{ref: ref, timer: timer}, holds} ->
        Process.demonitor(ref)
        Process.cancel_timer(timer, async: true, info: false)
        %{state | holds: holds, monitors: Map.delete(state.monitors, ref)}
    end
  end

  ## Subscribers

  defp add_subscriber(%{subscribers: subscribers} = state, pid)
       when is_map_key(subscribers, pid),
       do: state

  defp add_subscriber(state, pid) do
    :ets.insert(state.table, {{:subscriber, pid}, true})
    track_subscriber(state, pid)
  end

  defp track_subscriber(state, pid) do
    ref = Process.monitor(pid)

    %{
      state
      | subscribers: Map.put(state.subscribers, pid, ref),
        monitors: Map.put(state.monitors, ref, {:subscriber, pid})
    }
  end

  defp remove_subscriber(state, pid, ref) do
    :ets.delete(state.table, {:subscriber, pid})

    %{
      state
      | subscribers: Map.delete(state.subscribers, pid),
        monitors: Map.delete(state.monitors, ref)
    }
  end

  defp notify(state, seat, kind, fan) do
    event = {:seat_event, seat, kind, fan}
    Enum.each(state.subscribers, fn {pid, _ref} -> send(pid, event) end)
  end

  ## Recovery

  # Rebuilds subscribers, monitors and timers from the table: on first boot
  # (empty table) and after every crash. Subscribers come first, so they get
  # the events emitted while holds are restored. A hold whose deadline passed
  # while the server was down expires immediately; a fan that died meanwhile
  # triggers an immediate :DOWN. Rows with an unexpected shape are reset rather
  # than trusted, so bad data cannot crash the server again on every restart.
  @spec restore(t) :: t
  defp restore(state) do
    {subscribers, other_rows} =
      state.table |> :ets.tab2list() |> Enum.split_with(&subscriber_row?/1)

    state =
      Enum.reduce(subscribers, state, fn {{:subscriber, pid}, _}, acc ->
        track_subscriber(acc, pid)
      end)

    Enum.each(other_rows, &drop_unless_seat(state, &1))
    Enum.reduce(1..SeatReservation.seat_count(), state, &restore_seat(&2, &1))
  end

  defp subscriber_row?({{:subscriber, pid}, true}), do: is_pid(pid)
  defp subscriber_row?(_row), do: false

  defp drop_unless_seat(state, row) do
    key = elem(row, 0)

    if not is_seat(key) do
      Logger.warning("#{inspect(__MODULE__)} dropped invalid row: #{inspect(row, limit: 10)}")
      :ets.delete(state.table, key)
    end
  end

  defp restore_seat(state, seat) do
    case :ets.lookup(state.table, seat) do
      [{^seat, :free}] ->
        state

      [{^seat, {:confirmed, fan}}] when is_pid(fan) ->
        state

      [{^seat, {:held, fan, deadline}}] when is_pid(fan) and is_integer(deadline) ->
        track_hold(state, seat, fan, deadline)

      [] ->
        write(state, seat, :free)
        state

      [row] ->
        Logger.warning(
          "#{inspect(__MODULE__)} reset seat #{seat}, invalid row: #{inspect(row, limit: 10)}"
        )

        write(state, seat, :free)
        state
    end
  end

  ## Helpers

  defp lookup(state, seat) do
    [{^seat, value}] = :ets.lookup(state.table, seat)
    value
  end

  defp write(state, seat, value), do: :ets.insert(state.table, {seat, value})

  defp public_state({:held, fan, _deadline}), do: {:held, fan}
  defp public_state(other), do: other

  defp now, do: System.monotonic_time(:millisecond)

  defp log_ignored(kind, term) do
    Logger.warning(
      "#{inspect(__MODULE__)} ignored #{kind}: #{inspect(term, limit: 10, printable_limit: 100)}"
    )
  end
end
