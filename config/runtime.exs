import Config

if config_env() == :prod do
  config :seat_reservation, SeatReservationWeb.Endpoint,
    secret_key_base: System.fetch_env!("SECRET_KEY_BASE"),
    url: [host: System.fetch_env!("PHX_HOST"), scheme: "https", port: 443],
    http: [port: String.to_integer(System.get_env("PORT") || "4000")]
end

if System.get_env("PHX_SERVER") do
  config :seat_reservation, SeatReservationWeb.Endpoint, server: true
end
