defmodule SeatReservation.Store do
  @moduledoc """
  Keeps the seat table alive while no `SeatReservation.Server` owns it.

  The table is created here with this process as its *heir* and handed to the
  server, which becomes its owner and only writer (the table is `:protected`).
  When the server crashes, the VM gives the table back to this process, and the
  restarted server claims it again. The server, not this module, decides what
  the table contains, so there is no seat logic here that could fail.
  """
  use GenServer

  require Logger

  @spec start_link(keyword) :: GenServer.on_start()
  def start_link(opts) do
    GenServer.start_link(__MODULE__, :ok, name: Keyword.fetch!(opts, :name))
  end

  @doc """
  Makes the calling process the owner of the table and returns it.

  If the previous owner has just crashed, the table may still be on its way
  back to the store. The reply is then held until the store owns it again.
  """
  @spec claim(GenServer.server()) :: {:ok, :ets.tid()}
  def claim(store), do: GenServer.call(store, :claim)

  @impl true
  def init(:ok) do
    table = :ets.new(__MODULE__, [:set, :protected, {:heir, self(), :returned}])
    {:ok, %{table: table, pending: nil}}
  end

  @impl true
  def handle_call(:claim, from, %{table: table} = state) do
    if :ets.info(table, :owner) == self() do
      {:noreply, hand_over(state, from)}
    else
      # The previous owner is still exiting. A newer claim replaces an older
      # one, whose caller has given up by now.
      {:noreply, %{state | pending: from}}
    end
  end

  def handle_call(request, _from, state) do
    Logger.warning("#{inspect(__MODULE__)} ignored call: #{inspect(request, limit: 10)}")
    {:reply, {:error, :invalid}, state}
  end

  @impl true
  def handle_cast(request, state) do
    Logger.warning("#{inspect(__MODULE__)} ignored cast: #{inspect(request, limit: 10)}")
    {:noreply, state}
  end

  @impl true
  def handle_info({:"ETS-TRANSFER", table, _from, _data}, %{table: table, pending: nil} = state) do
    {:noreply, state}
  end

  def handle_info({:"ETS-TRANSFER", table, _from, _data}, %{table: table, pending: from} = state) do
    {:noreply, hand_over(state, from)}
  end

  def handle_info(message, state) do
    Logger.warning("#{inspect(__MODULE__)} ignored message: #{inspect(message, limit: 10)}")
    {:noreply, state}
  end

  # Gives the table to the claiming process. If that process died while
  # waiting, give_away/3 raises; the store then keeps the table for the next
  # claim instead of crashing and taking the table down with it.
  defp hand_over(%{table: table} = state, {pid, _tag} = from) do
    :ets.give_away(table, pid, :claimed)
    GenServer.reply(from, {:ok, table})
    %{state | pending: nil}
  rescue
    ArgumentError -> %{state | pending: nil}
  end
end
