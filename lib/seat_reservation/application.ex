defmodule SeatReservation.Application do
  @moduledoc false
  use Application

  @impl true
  def start(_type, _args) do
    seat_children =
      for seat <- 1..SeatReservation.seat_count() do
        Supervisor.child_spec({SeatReservation.Seat, seat}, id: {SeatReservation.Seat, seat})
      end

    children = [
      {Registry, keys: :duplicate, name: SeatReservation.Subscribers},
      {Phoenix.PubSub, name: SeatReservation.PubSub},
      SeatReservation.TableManager,
      SeatReservationWeb.Endpoint
      | seat_children
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: SeatReservation.Supervisor)
  end
end
