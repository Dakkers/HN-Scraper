defmodule HNScraper.Mixfile do
  use Mix.Project

  def project do
    [app: :hnscraper,
     version: "0.0.1",
     elixir: "~> 1.0",
     build_embedded: Mix.env == :prod,
     start_permanent: Mix.env == :prod,
     deps: deps]
  end

  def application do
    [mod: {HNScraper.App, []},
     applications: [:logger, :postgrex, :ecto, :quantum]]
  end

  defp deps do
    [
      {:hnapi, git: "https://github.com/SaintDako/hnAPI-elixir.git", branch: "master"},
      {:postgrex, ">= 0.0.0"},
      {:ecto, "~> 0.13.0"},
      {:quantum, ">= 1.2.4"}
    ]
  end
end
