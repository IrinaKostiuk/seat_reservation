defmodule SeatReservation.MixProject do
  use Mix.Project

  def project do
    [
      app: :seat_reservation,
      version: "0.1.0",
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {SeatReservation.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:phoenix, "~> 1.7.14"},
      {:phoenix_html, "~> 4.1"},
      {:phoenix_live_view, "~> 0.20.14"},
      {:bandit, "~> 1.5"},
      {:jason, "~> 1.4"},
      {:floki, ">= 0.30.0", only: :test}
    ]
  end
end
