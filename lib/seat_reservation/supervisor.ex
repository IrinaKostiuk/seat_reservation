defmodule SeatReservation.Supervisor do
  @moduledoc """
  Supervises the seat store and the seat server.

  The strategy is `:rest_for_one` because the server depends on the store. A
  server crash restarts only the server, which reclaims the table from the
  store, so no seat data is lost. If the store itself ever restarted, the
  server would restart after it.

  Options:

    * `:name` - base name for the processes (default `SeatReservation`). The
      server is registered as `<name>.Server` and the store as `<name>.Store`.
    * `:hold_timeout_ms` - how long a hold lasts (default
      `SeatReservation.hold_timeout_ms/0`).
  """
  use Supervisor

  @spec start_link(keyword) :: Supervisor.on_start()
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, SeatReservation)
    Supervisor.start_link(__MODULE__, opts, name: Module.concat(name, Supervisor))
  end

  @doc "The registered name of the seat server for the given base name."
  @spec server_name(atom) :: atom
  def server_name(name \\ SeatReservation), do: Module.concat(name, Server)

  @impl true
  def init(opts) do
    name = Keyword.get(opts, :name, SeatReservation)
    store = Module.concat(name, Store)

    children = [
      {SeatReservation.Store, name: store},
      {SeatReservation.Server,
       name: server_name(name),
       store: store,
       hold_timeout_ms: Keyword.get(opts, :hold_timeout_ms, SeatReservation.hold_timeout_ms())}
    ]

    Supervisor.init(children, strategy: :rest_for_one)
  end
end
