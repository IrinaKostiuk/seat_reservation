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
      {:phoenix, "~> 1.7.0"},
      {:phoenix_live_view, "~> 1.0.0"},
      {:phoenix_html, "~> 4.1"},
      # Stay compatible with the exercise's Elixir 1.15 runtime.
      {:phoenix_template, "~> 1.0.0"},
      {:plug, "~> 1.19.0"},
      {:bandit, "~> 1.12.5"},
      {:jason, "~> 1.4"},
      {:floki, "~> 0.36.0", only: :test}
    ]
  end
end
