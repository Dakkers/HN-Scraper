# Schemas
defmodule Counts do
  use Ecto.Model

  schema "counts" do
    field :word,  :string
    field :count, :integer
  end
end

defmodule Posts do
  use Ecto.Model

  schema "posts" do
    field :post_id, :integer
    field :url,     :string
  end
end

# setting up stuff
defmodule HNScraper.App do
  use Application

  def start(_type, _args) do
    import Supervisor.Spec
    tree = [worker(HNScraper.Repo, [])]
    opts = [name: HNScraper.Sup, strategy: :one_for_one]
    Supervisor.start_link(tree, opts)
  end
end

defmodule HNScraper.Repo do
  use Ecto.Repo,
    otp_app: :hnscraper
end

# actual functions
defmodule HNScraper do
  import Ecto.Query

  def replace_punc(s) do
    Regex.replace(~r/[^a-zA-Z_']/, s, " ")
  end

  def remove_multiple_spaces(s) do
    Regex.replace(~r/ {2,}/, s, " ")
  end

  def word_in_db?(w) do
    query = from row in Counts,
      where: row.word == ^w,
      select: row.word
    Enum.count(HNScraper.Repo.all(query)) == 1
  end

  def post_in_db?(post_id) do
    query = from row in Posts,
      where: row.post_id == ^post_id,
      select: row.post_id
    Enum.count(HNScraper.Repo.all(query)) == 1
  end

  def url_in_db?(url) do
    query = from row in Posts,
      where: row.url == ^url,
      select: row.url
    Enum.count(HNScraper.Repo.all(query)) == 1
  end
end
