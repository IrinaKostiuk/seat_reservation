defmodule SeatReservation.Seat do
  @moduledoc false
  use GenServer

  @table_name :seat_reservation_seats
  @pubsub SeatReservation.Subscribers
  @event_topic "events"

  def process_name(seat) when is_integer(seat) do
    :"seat_reservation_seat_#{seat}"
  end

  def start_link(seat) when is_integer(seat) do
    GenServer.start_link(__MODULE__, seat, name: process_name(seat))
  end

  def hold(seat, fan) do
    GenServer.call(process_name(seat), {:hold, fan})
  end

  def confirm(seat, fan) do
    GenServer.call(process_name(seat), {:confirm, fan})
  end

  def release(seat, fan) do
    GenServer.call(process_name(seat), {:release, fan})
  end

  # Server Callbacks

  @impl true
  def init(seat) do
    :ets.insert(@table_name, {seat, :free})
    {:ok, %{seat: seat, status: :free}}
  end

  @impl true
  def handle_call({:hold, fan}, _from, %{status: :free, seat: seat} = state) do
    ref = Process.monitor(fan)
    timer_ref = Process.send_after(self(), :hold_timeout, SeatReservation.hold_timeout_ms())
    :ets.insert(@table_name, {seat, {:held, fan}})
    broadcast(seat, :held, fan)
    {:reply, :ok, %{state | status: {:held, fan, ref, timer_ref}}}
  end

  def handle_call({:hold, _fan}, _from, state) do
    {:reply, {:error, :taken}, state}
  end

  def handle_call(
        {:confirm, fan},
        _from,
        %{status: {:held, fan, ref, timer_ref}, seat: seat} = state
      ) do
    Process.demonitor(ref, [:flush])
    Process.cancel_timer(timer_ref)
    :ets.insert(@table_name, {seat, {:confirmed, fan}})
    broadcast(seat, :confirmed, fan)
    {:reply, :ok, %{state | status: {:confirmed, fan}}}
  end

  def handle_call({:confirm, _fan}, _from, state) do
    {:reply, {:error, :not_held}, state}
  end

  def handle_call(
        {:release, fan},
        _from,
        %{status: {:held, fan, ref, timer_ref}, seat: seat} = state
      ) do
    Process.demonitor(ref, [:flush])
    Process.cancel_timer(timer_ref)
    :ets.insert(@table_name, {seat, :free})
    broadcast(seat, :released, fan)
    {:reply, :ok, %{state | status: :free}}
  end

  def handle_call({:release, fan}, _from, %{status: {:confirmed, fan}, seat: seat} = state) do
    :ets.insert(@table_name, {seat, :free})
    broadcast(seat, :released, fan)
    {:reply, :ok, %{state | status: :free}}
  end

  def handle_call({:release, _fan}, _from, state) do
    {:reply, :ok, state}
  end

  @impl true
  def handle_info(
        {:DOWN, ref, :process, fan, _reason},
        %{status: {:held, fan, ref, timer_ref}, seat: seat} = state
      ) do
    Process.cancel_timer(timer_ref)
    :ets.insert(@table_name, {seat, :free})
    broadcast(seat, :released, fan)
    {:noreply, %{state | status: :free}}
  end

  def handle_info({:DOWN, _ref, :process, _pid, _reason}, state) do
    {:noreply, state}
  end

  def handle_info(:hold_timeout, %{status: {:held, fan, ref, _timer_ref}, seat: seat} = state) do
    Process.demonitor(ref, [:flush])
    :ets.insert(@table_name, {seat, :free})
    broadcast(seat, :released, fan)
    {:noreply, %{state | status: :free}}
  end

  def handle_info(:hold_timeout, state) do
    {:noreply, state}
  end

  defp broadcast(seat, event_type, fan) do
    Registry.dispatch(@pubsub, @event_topic, fn entries ->
      for {pid, _} <- entries do
        send(pid, {:seat_event, seat, event_type, fan})
      end
    end)
  end
end
