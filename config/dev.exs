import Config

# Binds to all interfaces because the server runs inside Docker (see bin/mix).
config :seat_reservation, SeatReservationWeb.Endpoint,
  http: [ip: {0, 0, 0, 0}, port: 4000],
  debug_errors: true,
  secret_key_base: "X9XICugFmnSQGEjvnWTUvsWILOQGBj6uunJc6Y96WnIiF0NBxWtN3N0vIMtP3LU6"
