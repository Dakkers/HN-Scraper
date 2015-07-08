use Mix.Config

config :hnscraper, HNScraper.Repo,
  adapter: Ecto.Adapters.Postgres,
  database: "HNScraper",
  username: "saintdako",
  password: "12345"