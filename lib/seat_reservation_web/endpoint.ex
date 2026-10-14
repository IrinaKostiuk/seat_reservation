defmodule SeatReservationWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :seat_reservation

  @session_options [
    store: :cookie,
    key: "_seat_reservation_key",
    signing_salt: "seat_cookie_salt_12345",
    same_site: "Lax"
  ]

  socket("/live", Phoenix.LiveView.Socket, websocket: [connect_info: [session: @session_options]])

  plug(Plug.RequestId)
  plug(Plug.Telemetry, event_prefix: [:phoenix, :endpoint])

  plug(Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    json_decoder: Phoenix.json_library()
  )

  plug(Plug.MethodOverride)
  plug(Plug.Head)
  plug(Plug.Session, @session_options)
  plug(SeatReservationWeb.Router)
end
