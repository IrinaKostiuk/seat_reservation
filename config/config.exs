import Config

config :seat_reservation, SeatReservationWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [formats: [html: SeatReservationWeb.ErrorHTML], layout: false],
  live_view: [signing_salt: "8wvyNUis6Jl2Uix4"]

config :phoenix, :json_library, Jason

import_config "#{config_env()}.exs"
