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

  # replace all punctuation except underscore and apostrophes with spaces
  def replace_punc(s) do
    Regex.replace(~r/[^a-zA-Z_']/, s, " ")
  end

  # remove multiple spaces
  def remove_multiple_spaces(s) do
    Regex.replace(~r/ {2,}/, s, " ")
  end

  # remove all spaces
  def remove_all_spaces(s) do
    Regex.replace(~r/ +/, s, "")
  end

  # format a single word
  def format_word(word) do
    word
    |> replace_punc
    |> remove_all_spaces
    |> String.downcase
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

  # increment the count of a given word
  # set the count to 1 if the word is not in the DB yet
  def increment_word_count(word) do
    if (word_in_db?(word)) do
      word_id = from(row in Counts, where: row.word == ^word, select: row.id)
      |> HNScraper.Repo.all
      |> hd

      c = HNScraper.Repo.get!(Counts, word_id)
      c = %{c | count: c.count+1}
      HNScraper.Repo.update!(c)
    else
      HNScraper.Repo.insert! %Counts{word: word, count: 1}
    end
    word
  end

  # get all post IDs with given word in title
  # format the word if format? is true
  def get_posts_with_word(word, format? \\ true) do
    if format? do
      word = HNScraper.Str.format_word(word)
    end
    from(row in Words, where: row.word == ^word, select: row.post_id)
    |> HNScraper.Repo.all
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

  # given all of the details about a post, extract the title, url and ID
  # and put them into a map
  def create_post_map(post) do
    %{
      :title => HNScraper.Str.format_title(post["title"]),   # a list!
      :url   => post["url"],
      :id    => post["id"]
    }
  end

  # scrape the top top_posts_amount (default to 500) by ID, remove posts whose ID
  # is already in DB, get their full details, remove asks, remove posts whose URL
  # is already in DB, get rid of info we don't care about, put stuff into DB.
  def scrape(top_posts_amount \\ 500) do
    HNAPI.top_stories_by_id("story", top_posts_amount)
    |> Enum.filter(&(not post_in_db?(&1)))
    |> Enum.map(&(HNAPI.get_item(&1)))
    |> Enum.filter(&(not is_ask?(&1)))
    |> Enum.filter(&(not url_in_db?(&1["url"])))
    |> Enum.map(&(create_post_map(&1)))
    |> Enum.map(&(insert_data_into_db(&1)))
  end

  # run the scraper at the given cronjob time, scraping the number of posts specified
  # by top_posts_amount
  def start_scraping(crontime \\ "0 * * * *", top_posts_amount \\ 500) do
    HNAPI.start
    HNScraper.Repo.start_link
    Quantum.add_job(crontime, fn -> scrape(top_posts_amount) end)   # hourly
  end
end
