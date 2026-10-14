defmodule SeatReservation.Application do
  @moduledoc false
  use Application

  @impl true
  def start(_type, _args) do
    children = [
      SeatReservation.Server,
      {Registry, keys: :unique, name: SeatReservation.BrowserRegistry},
      {DynamicSupervisor, strategy: :one_for_one, name: SeatReservation.BrowserSessions},
      {Phoenix.PubSub, name: SeatReservation.PubSub},
      SeatReservationWeb.Endpoint
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: SeatReservation.Supervisor)
  end

  @impl true
  def config_change(changed, _new, removed) do
    SeatReservationWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
