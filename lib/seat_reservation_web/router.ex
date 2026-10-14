defmodule SeatReservationWeb.Router do
  use SeatReservationWeb, :router

  pipeline :browser do
    plug(:accepts, ["html"])
    plug(:fetch_session)
    plug(:fetch_live_flash)
    plug(:put_root_layout, html: {SeatReservationWeb.Layouts, :root})
    plug(:protect_from_forgery)
    plug(:put_secure_browser_headers)
  end

  scope "/", SeatReservationWeb do
    pipe_through(:browser)

    live("/", SeatLive, :index)
  end
end
