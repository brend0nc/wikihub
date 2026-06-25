defmodule Wikihub.Parser do
  @moduledoc """
  Discovers wikis on disk and parses each into a `Wikihub.Wiki`.

  Discovery is driven by the `:wiki_paths` config (comma-separated paths or
  globs, set via the `WIKIHUB_PATHS` env var) and defaults to `~/*/wiki`. Each
  wiki is parsed by structure: `:pages` (a `pages/` subtree + `refs:` frontmatter
  + optional `log.md`) vs `:obsidian` (topic folders + `[[wikilinks]]` + `updated:`).
  """
  alias Wikihub.{Wiki, Page, Frontmatter}

  @doc "Parse every discovered wiki, concurrently, then resolve the link graph."
  def scan do
    discover()
    |> Task.async_stream(&parse_wiki/1, timeout: 30_000, on_timeout: :kill_task)
    |> Enum.flat_map(fn
      {:ok, wiki} -> [wiki]
      _ -> []
    end)
    |> compute_links()
    |> Enum.sort_by(&{&1.stub, &1.name})
  end

  @doc """
  Finds every wiki directory on disk. Reads `:wiki_paths` (comma-separated paths
  or globs; default `~/*/wiki`), expands each glob, keeps the directories, and
  drops any whose name is listed in `:ignore_wikis`. Dotfile dirs are included.
  """
  def discover do
    ignore = Application.get_env(:wikihub, :ignore_wikis, [])

    wiki_globs()
    |> Enum.flat_map(&Path.wildcard(&1, match_dot: true))
    |> Enum.filter(&File.dir?/1)
    |> Enum.uniq()
    |> Enum.reject(&(wiki_name(&1) in ignore))
  end

  defp wiki_globs do
    case Application.get_env(:wikihub, :wiki_paths) do
      blank when blank in [nil, ""] ->
        [Path.join(System.user_home!(), "*/wiki")]

      paths ->
        paths
        |> String.split(",", trim: true)
        |> Enum.map(&String.trim/1)
        |> Enum.reject(&(&1 == ""))
        |> Enum.map(&Path.expand/1)
    end
  end

  # A wiki is named after its own directory, except the co-located
  # `<project>/wiki` convention where it takes the project name (keeps URLs stable).
  defp wiki_name(path) do
    case Path.basename(path) do
      "wiki" -> path |> Path.dirname() |> Path.basename()
      name -> name
    end
  end

  defp parse_wiki(path) do
    name = wiki_name(path)
    dialect = if File.dir?(Path.join(path, "pages")), do: :pages, else: :obsidian
    pages = collect_pages(path, dialect, name)

    %Wiki{
      name: name,
      path: path,
      dialect: dialect,
      pages: pages,
      categories: Enum.frequencies_by(pages, & &1.category),
      log: parse_log(path),
      working: read_working(path),
      last_activity: last_activity(path, pages),
      bucket: bucket(last_activity(path, pages)),
      stub: pages == [],
      note: wiki_note(name, pages, path)
    }
  end

  # --- pages -----------------------------------------------------------------

  defp collect_pages(path, :pages, name) do
    Path.join(path, "pages/**/*.md")
    |> Path.wildcard()
    |> Enum.map(&build_page(&1, path, name, category_pages(&1, path)))
  end

  defp collect_pages(path, :obsidian, name) do
    topics =
      case File.ls(path) do
        {:ok, entries} -> entries
        {:error, _} -> []
      end

    topics
    |> Enum.filter(&File.dir?(Path.join(path, &1)))
    |> Enum.reject(&(&1 in ["raw", ".obsidian", ".git"]))
    |> Enum.flat_map(fn topic ->
      [path, topic, "**/*.md"]
      |> Path.join()
      |> Path.wildcard()
      |> Enum.reject(&(Path.basename(&1) == "_overview.md"))
      |> Enum.map(&build_page(&1, path, name, topic))
    end)
  end

  defp category_pages(file, wiki) do
    case file |> Path.relative_to(Path.join(wiki, "pages")) |> Path.split() do
      [cat, _ | _] -> cat
      _ -> "misc"
    end
  end

  defp build_page(file, _wiki, wname, category) do
    content =
      case File.read(file) do
        {:ok, c} -> c
        _ -> ""
      end

    {fm, body} = Frontmatter.parse(content)

    %Page{
      id: file |> Path.basename() |> Path.rootname(),
      wiki: wname,
      path: file,
      category: category,
      title: fm["title"] || file |> Path.basename() |> Path.rootname(),
      date: page_date(fm, file),
      refs: extract_refs(fm, body),
      sources: fm["sources"] |> List.wrap() |> Enum.reject(&(&1 in [nil, ""])),
      excerpt: excerpt(body),
      inbound: 0
    }
  end

  # A short, whitespace-collapsed preview of the body, used in lists and search.
  defp excerpt(body) do
    body
    |> String.replace(~r/[#>*`]/, " ")
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
    |> String.slice(0, 200)
  end

  defp extract_refs(fm, body) do
    fm_refs = fm["refs"] |> List.wrap() |> Enum.reject(&(&1 in [nil, ""]))

    wiki_refs =
      ~r/\[\[([^\]\|]+)(?:\|[^\]]*)?\]\]/
      |> Regex.scan(body)
      |> Enum.map(fn [_, t] -> t |> Path.basename() |> String.trim() end)

    Enum.uniq(fm_refs ++ wiki_refs)
  end

  # --- dates -----------------------------------------------------------------

  defp page_date(fm, file) do
    parse_date(fm["last_modified"] || fm["updated"] || fm["created"]) || mtime_date(file)
  end

  defp parse_date(s) when is_binary(s) do
    case Date.from_iso8601(String.slice(s, 0, 10)) do
      {:ok, d} -> d
      _ -> nil
    end
  end

  defp parse_date(_), do: nil

  defp mtime_date(file) do
    case File.stat(file, time: :posix) do
      {:ok, %{mtime: m}} -> m |> DateTime.from_unix!() |> DateTime.to_date()
      _ -> nil
    end
  end

  defp last_activity(path, pages) do
    page_dates = pages |> Enum.map(& &1.date) |> Enum.reject(&is_nil/1)

    file_dates =
      Path.join(path, "*.md")
      |> Path.wildcard()
      |> Enum.map(&mtime_date/1)
      |> Enum.reject(&is_nil/1)

    (page_dates ++ file_dates) |> Enum.sort({:desc, Date}) |> List.first()
  end

  defp bucket(nil), do: :empty

  defp bucket(date) do
    case Date.diff(Date.utc_today(), date) do
      d when d <= 7 -> :fresh
      d when d <= 14 -> :aging
      _ -> :stale
    end
  end

  # --- log / working ---------------------------------------------------------

  defp parse_log(path) do
    case File.read(Path.join(path, "log.md")) do
      {:ok, content} ->
        ~r/^##\s*\[(\d{4}-\d{2}-\d{2})\]\s*([^\|\n]+?)\s*\|\s*(.+)$/m
        |> Regex.scan(content)
        |> Enum.map(fn [_, date, op, title] ->
          %{date: date, op: String.trim(op), title: String.trim(title)}
        end)

      _ ->
        []
    end
  end

  defp read_working(path) do
    case File.read(Path.join(path, "WORKING.md")) do
      {:ok, c} ->
        c
        |> String.split("\n")
        |> Enum.map(&String.trim/1)
        |> Enum.find(&(&1 != "" and not String.starts_with?(&1, "#")))

      _ ->
        nil
    end
  end

  defp wiki_note(_name, [], path) do
    if File.exists?(Path.join(path, "log.md")), do: "empty scaffold", else: "no pages"
  end

  defp wiki_note(_name, _pages, path) do
    if File.exists?(Path.join(path, "log.md")), do: nil, else: "no log.md — using file times"
  end

  # --- link graph ------------------------------------------------------------

  defp compute_links(wikis) do
    Enum.map(wikis, fn w ->
      ids = MapSet.new(w.pages, & &1.id)
      inbound = w.pages |> Enum.flat_map(& &1.refs) |> Enum.frequencies()

      pages = Enum.map(w.pages, &%{&1 | inbound: Map.get(inbound, &1.id, 0)})

      broken =
        w.pages
        |> Enum.flat_map(fn p -> Enum.map(p.refs, &{p.id, &1}) end)
        |> Enum.reject(fn {_from, to} -> MapSet.member?(ids, to) end)

      %{
        w
        | pages: pages,
          orphans: pages |> Enum.filter(&(&1.inbound == 0)) |> Enum.map(& &1.id),
          broken_refs: broken,
          unsourced: pages |> Enum.filter(&(&1.sources == [])) |> Enum.map(& &1.id)
      }
    end)
  end
end
