defmodule SeatReservation.Server do
  @moduledoc false
  use GenServer

  @seat_count SeatReservation.seat_count()

  defguardp valid_request(seat, fan)
            when is_integer(seat) and seat >= 1 and seat <= @seat_count and is_pid(fan)

  def start_link(_opts), do: GenServer.start_link(__MODULE__, [], name: __MODULE__)

  @impl true
  def init(_) do
    {:ok,
     %{
       seats: Map.new(1..@seat_count, &{&1, :free}),
       holds: %{},
       fans: %{},
       subscribers: %{}
     }}
  end

  @impl true
  def handle_call(request, from, state) do
    # A timer can be queued behind a call. Deadlines, rather than mailbox order,
    # decide whether that call still owns a live hold.
    {reply, state} = dispatch(request, from, expire_due(state))
    {:reply, reply, state}
  end

  defp dispatch({:hold, seat, fan}, _from, state) when valid_request(seat, fan) do
    if state.seats[seat] == :free do
      token = make_ref()
      deadline = now() + SeatReservation.hold_timeout_ms()

      timer =
        Process.send_after(self(), {:expire, seat, token}, SeatReservation.hold_timeout_ms())

      hold = %{fan: fan, token: token, timer: timer, deadline: deadline}

      owner =
        case state.fans[fan] do
          nil -> %{ref: Process.monitor(fan), seats: MapSet.new([seat])}
          owner -> %{owner | seats: MapSet.put(owner.seats, seat)}
        end

      state = %{
        state
        | holds: Map.put(state.holds, seat, hold),
          fans: Map.put(state.fans, fan, owner)
      }

      {:ok, transition(state, seat, {:held, fan}, :held, fan)}
    else
      {{:error, :taken}, state}
    end
  end

  defp dispatch({:confirm, seat, fan}, _from, state) when valid_request(seat, fan) do
    case state.seats[seat] do
      {:held, ^fan} ->
        state = drop_hold(state, seat)
        {:ok, transition(state, seat, {:confirmed, fan}, :confirmed, fan)}

      _ ->
        {{:error, :not_held}, state}
    end
  end

  defp dispatch({:release, seat, fan}, _from, state) when valid_request(seat, fan) do
    case state.seats[seat] do
      {kind, ^fan} when kind in [:held, :confirmed] -> {:ok, release_seat(state, seat, fan)}
      _ -> {:ok, state}
    end
  end

  defp dispatch({:release, _, _}, _from, state), do: {:ok, state}

  defp dispatch(:subscribe, {pid, _tag}, state) do
    subscribers = Map.put_new_lazy(state.subscribers, pid, fn -> Process.monitor(pid) end)
    {:ok, %{state | subscribers: subscribers}}
  end

  defp dispatch(:seats, _from, state), do: {state.seats, state}
  defp dispatch(_request, _from, state), do: {{:error, :invalid}, state}

  @impl true
  def handle_info({:expire, seat, token}, state) do
    case state.holds[seat] do
      %{token: ^token} -> {:noreply, expire_due(state)}
      _ -> {:noreply, state}
    end
  end

  def handle_info({:DOWN, ref, :process, pid, _reason}, state) do
    state =
      case state.fans[pid] do
        %{ref: ^ref, seats: seats} ->
          Enum.reduce(seats, state, fn seat, acc -> release_seat(acc, seat, pid) end)

        _ ->
          state
      end

    state =
      if Map.get(state.subscribers, pid) == ref do
        %{state | subscribers: Map.delete(state.subscribers, pid)}
      else
        state
      end

    {:noreply, state}
  end

  def handle_info(_message, state), do: {:noreply, state}

  @impl true
  def handle_cast(_message, state), do: {:noreply, state}

  defp expire_due(state) do
    time = now()

    Enum.reduce(state.holds, state, fn {seat, hold}, acc ->
      if hold.deadline <= time, do: release_seat(acc, seat, hold.fan), else: acc
    end)
  end

  defp release_seat(state, seat, fan) do
    state = drop_hold(state, seat)
    transition(state, seat, :free, :released, fan)
  end

  defp drop_hold(state, seat) do
    case Map.pop(state.holds, seat) do
      {nil, _holds} ->
        state

      {hold, holds} ->
        Process.cancel_timer(hold.timer)
        owner = Map.fetch!(state.fans, hold.fan)
        seats = MapSet.delete(owner.seats, seat)

        fans =
          if MapSet.size(seats) == 0 do
            Process.demonitor(owner.ref, [:flush])
            Map.delete(state.fans, hold.fan)
          else
            Map.put(state.fans, hold.fan, %{owner | seats: seats})
          end

        %{state | holds: holds, fans: fans}
    end
  end

  defp transition(state, seat, value, event, fan) do
    Enum.each(state.subscribers, fn {pid, _ref} ->
      send(pid, {:seat_event, seat, event, fan})
    end)

    %{state | seats: Map.put(state.seats, seat, value)}
  end

  defp now, do: System.monotonic_time(:millisecond)
end
