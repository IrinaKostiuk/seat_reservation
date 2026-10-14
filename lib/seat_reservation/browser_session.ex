defmodule SeatReservation.BrowserSession do
  @moduledoc """
  Gives a signed browser session a stable fan PID across LiveView reconnects.
  The last tab disconnecting releases holds; confirmations keep their owner.
  Empty, disconnected sessions are discarded after one minute.
  """
  use GenServer, restart: :temporary

  def action(pid, action, seat), do: GenServer.call(pid, {:action, action, seat})

  def connect(browser_id) do
    pid =
      case DynamicSupervisor.start_child(
             SeatReservation.BrowserSessions,
             {__MODULE__, browser_id}
           ) do
        {:ok, pid} -> pid
        {:error, {:already_started, pid}} -> pid
      end

    :ok = GenServer.call(pid, :attach)
    pid
  end

  def start_link(browser_id) do
    GenServer.start_link(__MODULE__, [],
      name: {:via, Registry, {SeatReservation.BrowserRegistry, browser_id}}
    )
  end

  @impl true
  def init(_), do: {:ok, schedule_idle(%{clients: %{}, idle: nil})}

  @impl true
  def handle_call(:attach, {pid, _tag}, state) do
    if state.idle, do: Process.cancel_timer(state.idle.timer)
    clients = Map.put_new_lazy(state.clients, pid, fn -> Process.monitor(pid) end)
    {:reply, :ok, %{state | clients: clients, idle: nil}}
  end

  def handle_call({:action, action, seat}, {pid, _tag}, state) do
    # Serialize browser actions with disconnect cleanup, so a simultaneous
    # confirmation cannot turn a hold into a booking between inspection/release.
    result =
      if Map.has_key?(state.clients, pid) do
        case action do
          "hold" -> SeatReservation.hold(seat, self())
          "confirm" -> SeatReservation.confirm(seat, self())
          "release" -> SeatReservation.release(seat, self())
          _ -> {:error, :invalid}
        end
      else
        {:error, :invalid}
      end

    {:reply, result, state}
  end

  @impl true
  def handle_info({:DOWN, ref, :process, pid, _reason}, state) do
    clients =
      if state.clients[pid] == ref,
        do: Map.delete(state.clients, pid),
        else: state.clients

    state = %{state | clients: clients}

    if map_size(clients) == 0 do
      for {seat, {:held, fan}} <- SeatReservation.seats(), fan == self() do
        SeatReservation.release(seat, self())
      end

      {:noreply, schedule_idle(state)}
    else
      {:noreply, state}
    end
  end

  def handle_info({:idle, token}, %{idle: %{token: token}} = state) do
    owns_seats? =
      Enum.any?(SeatReservation.seats(), fn
        {_seat, {_status, fan}} -> fan == self()
        _ -> false
      end)

    if map_size(state.clients) == 0 and not owns_seats?,
      do: {:stop, :normal, state},
      else: {:noreply, %{state | idle: nil}}
  end

  def handle_info(_, state), do: {:noreply, state}

  defp schedule_idle(state) do
    if state.idle, do: Process.cancel_timer(state.idle.timer)
    token = make_ref()
    timer = Process.send_after(self(), {:idle, token}, 60_000)
    %{state | idle: %{token: token, timer: timer}}
  end
end
