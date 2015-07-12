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
    # ID is implicitly created
    field :url, :string
  end
end

defmodule Words do
  use Ecto.Model

  schema "words" do 
    field :word, :string
    field :post_id, :integer
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


# string helpers
defmodule HNScraper.Str do
  def replace_punc(s) do
    Regex.replace(~r/[^a-zA-Z_']/, s, " ")
  end

  def remove_multiple_spaces(s) do
    Regex.replace(~r/ {2,}/, s, " ")
  end

  def format_title(title) do
    title
    |> replace_punc
    |> remove_multiple_spaces
    |> String.downcase
    |> String.split(" ")
    |> Enum.filter(&(String.length(&1) > 1))
  end
end


defmodule HNScraper do
  HNAPI.start
  import Ecto.Query

  # DATABASE HELPERS
  # check if word exists in the Counts table (not the Words table, because the
  # Enum.count call will be faster this way. #yolo)
  def word_in_db?(word) do
    query = from row in Counts,
      where: row.word == ^word,
      select: row.word
    Enum.count(HNScraper.Repo.all(query)) == 1
  end

  # check if post ID exists in the database
  def post_in_db?(post_id) do
    query = from row in Posts,
      where: row.id == ^post_id,
      select: row.id
    Enum.count(HNScraper.Repo.all(query)) == 1
  end

  # check if URL exists in the database
  def url_in_db?(url) do
    query = from row in Posts,
      where: row.url == ^url,
      select: row.url
    Enum.count(HNScraper.Repo.all(query)) == 1
  end

  # insert a word from a title into the "Words" table
  def insert_word_into_db(word, post_id) do
    HNScraper.Repo.insert! %Words{post_id: post_id, word: word}
    word
  end

  # THIS IS NOT CURRENTLY WORKING ~~~~~~~~~~~~~~~~~~~~~~~~~
  def increment_word_count(word) do
    if (word_in_db?(word)) do
      word_id = from(row in Counts, where: row.word == ^word, select: row.id)
      |> HNScraper.Repo.all
      |> hd

      # query = from(row in Counts) |> where([row], row.word == ^word) |> update([row], inc: [count: 1])
      # query = from(row in Counts, where: row.word == ^word, update: [set: [count: ^(current_count + 1)]])
      # HNScraper.Repo.all(query)
      c = HNScraper.Repo.get!(Counts, word_id)
      c = %{c | count: c.count+1}
      HNScraper.Repo.update!(c)
    else
      HNScraper.Repo.insert! %Counts{word: word, count: 1}
    end
    word
  end

  # insert all stuff into the database!
  def insert_data_into_db(post) do
    post_id = post[:id]
    Enum.map(post[:title], &(increment_word_count(&1)))
    HNScraper.Repo.insert! %Posts{id: post_id, url: post[:url]}
    Enum.map(post[:title], &(insert_word_into_db(&1, post_id)))
    post
  end

  # check if post is ask type, in case post wasn't tagged correctly
  def is_ask?(post) do
    Regex.match?(~r/^Ask HN:/, post["title"])
  end

  def create_post_map(post) do
    %{
      :title => HNScraper.Str.format_title(post["title"]),   # a list!
      :url   => post["url"],
      :id    => post["id"]
    }
  end

  def scrape() do
    HNAPI.top_stories_by_id("story", 5)
    |> Enum.filter(&(not post_in_db?(&1)))
    |> Enum.map(&(HNAPI.get_item(&1)))
    |> Enum.filter(&(not is_ask?(&1)))
    |> Enum.filter(&(not url_in_db?(&1["url"])))
    |> Enum.map(&(create_post_map(&1)))
    |> Enum.map(&(insert_data_into_db(&1)))
  end

  def start_scraping() do
    HNAPI.start
    HNScraper.Repo.start_link
    Quantum.add_job("*/2 * * * *", fn -> scrape() end)
  end
end
