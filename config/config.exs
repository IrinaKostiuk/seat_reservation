import Config

config :seat_reservation, SeatReservationWeb.Endpoint,
  url: [host: "localhost"],
  http: [ip: {0, 0, 0, 0}, port: 4000],
  adapter: Bandit.PhoenixAdapter,
  secret_key_base: "local-development-only-seat-reservation-secret-key-base-000000000000000000",
  live_view: [signing_salt: "seat-live"],
  pubsub_server: SeatReservation.PubSub,
  render_errors: [formats: [html: SeatReservationWeb.ErrorHTML], layout: false]

config :phoenix, :json_library, Jason

if config_env() == :test do
  config :logger, level: :warning
  config :seat_reservation, SeatReservationWeb.Endpoint, server: false
end

if config_env() == :dev do
  config :seat_reservation, SeatReservationWeb.Endpoint,
    check_origin: ["//localhost", "//127.0.0.1"]
end
