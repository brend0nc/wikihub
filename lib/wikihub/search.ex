defmodule Wikihub.Search do
  @moduledoc """
  Cross-wiki search over the in-memory model. Matches wiki names and page
  title/id/category/excerpt, case-insensitively. Returns `nil` for a blank
  query so callers can cheaply decide whether to show the results overlay.
  """

  @spec run([map], String.t() | nil) :: %{wikis: [map], pages: [{String.t(), map}]} | nil
  def run(wikis, q) do
    needle = q |> to_string() |> String.trim() |> String.downcase()
    if needle == "", do: nil, else: do_run(wikis, needle)
  end

  defp do_run(wikis, needle) do
    %{
      wikis:
        wikis
        |> Enum.filter(&String.contains?(String.downcase(&1.name), needle))
        |> Enum.take(8),
      pages:
        wikis
        |> Enum.flat_map(fn w -> Enum.map(w.pages, &{w.name, &1}) end)
        |> Enum.filter(fn {_w, p} -> page_matches?(p, needle) end)
        |> Enum.sort_by(fn {wn, p} -> {wn, p.id} end)
        |> Enum.take(40)
    }
  end

  defp page_matches?(p, needle) do
    "#{p.title} #{p.id} #{p.category} #{p.excerpt}"
    |> String.downcase()
    |> String.contains?(needle)
  end
end
