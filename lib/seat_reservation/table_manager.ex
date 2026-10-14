defmodule SeatReservation.TableManager do
  @moduledoc false
  use GenServer

  @table_name :seat_reservation_seats

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    table = :ets.new(@table_name, [:set, :public, :named_table, read_concurrency: true])

    for seat <- 1..SeatReservation.seat_count() do
      :ets.insert(table, {seat, :free})
    end

    {:ok, %{table: table}}
  end
end
