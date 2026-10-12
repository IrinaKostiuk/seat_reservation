defmodule SeatReservationWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :seat_reservation

  @session_options [
    store: :cookie,
    key: "_seat_reservation",
    signing_salt: "seat-session",
    same_site: "Lax",
    http_only: true
  ]

  socket("/live", Phoenix.LiveView.Socket,
    websocket: [connect_info: [session: @session_options]],
    longpoll: false
  )

  plug(Plug.Static, at: "/", from: :seat_reservation, only: ~w(assets))

  # Serve the JS clients shipped with the locked dependencies, with no Node build.
  plug(Plug.Static,
    at: "/vendor/phoenix",
    from: {:phoenix, "priv/static"},
    only: ~w(phoenix.mjs)
  )

  plug(Plug.Static,
    at: "/vendor/live-view",
    from: {:phoenix_live_view, "priv/static"},
    only: ~w(phoenix_live_view.esm.js)
  )

  plug(Plug.RequestId)
  plug(Plug.Telemetry, event_prefix: [:phoenix, :endpoint])
  plug(Plug.Parsers, parsers: [:urlencoded, :multipart, :json], json_decoder: Jason)
  plug(Plug.MethodOverride)
  plug(Plug.Head)
  plug(Plug.Session, @session_options)
  plug(SeatReservationWeb.Router)
end
