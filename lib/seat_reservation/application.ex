defmodule SeatReservation.Application do
  @moduledoc false
  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # Add your processes here, e.g.
      # SeatReservation.Server,
      # {Registry, keys: :duplicate, name: SeatReservation.Subscribers}
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: SeatReservation.Supervisor)
  end
end
