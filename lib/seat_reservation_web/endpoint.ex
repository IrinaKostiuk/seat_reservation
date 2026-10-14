defmodule SeatReservationWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :seat_reservation

  # The session is stored in a signed cookie. LiveView reads it to verify the
  # CSRF token when the browser opens its socket.
  @session_options [
    store: :cookie,
    key: "_seat_reservation_key",
    signing_salt: "nCAQg9nw",
    same_site: "Lax"
  ]

  socket "/live", Phoenix.LiveView.Socket,
    websocket: [connect_info: [session: @session_options]],
    longpoll: false

  plug Plug.Static, at: "/", from: :seat_reservation, only: ~w(assets)

  # LiveView's prebuilt client, served straight from the dependencies, so the
  # project needs no JavaScript build step.
  plug Plug.Static, at: "/vendor", from: {:phoenix, "priv/static"}, only: ~w(phoenix.min.js)

  plug Plug.Static,
    at: "/vendor",
    from: {:phoenix_live_view, "priv/static"},
    only: ~w(phoenix_live_view.min.js)

  plug Plug.RequestId
  plug Plug.Telemetry, event_prefix: [:phoenix, :endpoint]

  plug Plug.Parsers,
    parsers: [:urlencoded],
    pass: ["*/*"]

  plug Plug.Head
  plug Plug.Session, @session_options
  plug SeatReservationWeb.Router
end
