import Config

config :seat_reservation, SeatReservationWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "pmvRTJ7ZQSXi1KqHR0LElbI9NGwoWj9UZchIXZyFbcqsNmysh7W6VmkwlqPNzbJn",
  server: false

config :logger, level: :warning

config :phoenix_live_view, enable_expensive_runtime_checks: true
