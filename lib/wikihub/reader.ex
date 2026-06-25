defmodule Wikihub.Reader do
  @moduledoc """
  Loads a wiki page from disk and renders its markdown to HTML for the in-browser
  reader. Rewrites `[[wikilinks]]` and relative `*.md` links into reader routes so
  navigation works inside the browser.
  """
  alias Wikihub.Frontmatter

  @spec render_page(map, String.t()) ::
          {:ok, struct, String.t(), [String.t()]} | :error
  def render_page(wiki, page_id) do
    case Enum.find(wiki.pages, &(&1.id == page_id)) || aux_page(wiki, page_id) do
      %Wikihub.Page{} = page -> do_render(wiki, page, page_id)
      _ -> :error
    end
  end

  # Overview/schema/index files aren't counted as content pages, but stay readable.
  defp aux_page(wiki, page_id) do
    case [wiki.path, "**", page_id <> ".md"] |> Path.join() |> Path.wildcard() |> List.first() do
      nil -> nil
      path -> %Wikihub.Page{id: page_id, wiki: wiki.name, title: page_id, path: path}
    end
  end

  defp do_render(wiki, page, page_id) do
    case File.read(page.path) do
      {:ok, raw} ->
        {_fm, body} = Frontmatter.parse(raw)
        html = body |> rewrite_links(wiki.name) |> Earmark.as_html!()

        backlinks =
          wiki.pages
          |> Enum.filter(&(page_id in &1.refs))
          |> Enum.map(& &1.id)
          |> Enum.sort()

        {:ok, page, html, backlinks}

      _ ->
        :error
    end
  end

  defp rewrite_links(body, wiki) do
    body
    |> replace(~r/\[\[([^\]\|]+)\|([^\]]+)\]\]/, fn _f, t, a ->
      "[#{a}](/r/#{wiki}/#{slug(t)})"
    end)
    |> replace(~r/\[\[([^\]\|]+)\]\]/, fn _f, t ->
      "[#{t}](/r/#{wiki}/#{slug(t)})"
    end)
    |> replace(~r/\]\(([^)\s]+?\.md)(#[^)]*)?\)/, fn _f, path, _anchor ->
      "](/r/#{wiki}/#{slug(path)})"
    end)
  end

  defp replace(str, re, fun), do: Regex.replace(re, str, fun)

  defp slug(t), do: t |> String.trim() |> Path.basename() |> String.replace_suffix(".md", "")
end
