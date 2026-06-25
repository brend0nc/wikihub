defmodule Wikihub.Panels do
  @moduledoc "Aggregates a list of wikis into the four dashboard panels."

  def build(wikis) do
    %{
      total_pages: wikis |> Enum.map(&length(&1.pages)) |> Enum.sum(),
      feed: feed(wikis),
      recent_pages: recent_pages(wikis),
      content_map: Enum.map(wikis, &{&1.name, &1.categories}),
      orphans: flat(wikis, fn w -> Enum.map(w.orphans, &{w.name, &1}) end),
      broken: flat(wikis, fn w -> Enum.map(w.broken_refs, fn {f, t} -> {w.name, f, t} end) end),
      unsourced_count: wikis |> Enum.map(&length(&1.unsourced)) |> Enum.sum()
    }
  end

  defp flat(wikis, fun), do: Enum.flat_map(wikis, fun)

  # Dated log entries across all wikis, newest first (ISO strings sort lexically).
  defp feed(wikis) do
    wikis
    |> Enum.flat_map(fn w -> Enum.map(w.log, &Map.put(&1, :wiki, w.name)) end)
    |> Enum.sort_by(& &1.date, :desc)
    |> Enum.take(20)
  end

  # Backstop for the feed: real files by mtime, so wikis with no log still show.
  defp recent_pages(wikis) do
    wikis
    |> Enum.flat_map(fn w -> Enum.map(w.pages, &{w.name, &1.id, &1.date}) end)
    |> Enum.reject(fn {_, _, d} -> is_nil(d) end)
    |> Enum.sort_by(fn {_, _, d} -> d end, {:desc, Date})
    |> Enum.take(12)
  end
end
