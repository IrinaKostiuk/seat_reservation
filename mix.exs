defmodule SeatReservation.MixProject do
  use Mix.Project

  def project do
    [
      app: :seat_reservation,
      version: "0.1.0",
      elixir: "~> 1.15",
      elixirc_paths: elixirc_paths(Mix.env()),
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

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_env), do: ["lib"]

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:phoenix, "~> 1.8.15"},
      {:phoenix_live_view, "~> 1.2.12"},
      {:phoenix_html, "~> 4.3"},
      {:bandit, "~> 1.12"},
      {:jason, "~> 1.4"},
      {:lazy_html, "~> 0.1", only: :test},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false}
    ]
  end
end
