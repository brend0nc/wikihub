defmodule WikihubWeb.ReaderLive do
  @moduledoc "Browses one wiki: a page list, and rendered individual pages with refs/backlinks."
  use WikihubWeb, :live_view
  alias Wikihub.{Scanner, Reader, Search}

  @impl true
  def mount(_params, _session, socket), do: {:ok, assign(socket, q: "", gq: "", gresults: nil)}

  @impl true
  def handle_event("search", %{"q" => q}, socket), do: {:noreply, assign(socket, q: q)}

  def handle_event("global_search", %{"q" => q}, socket) do
    {:noreply, assign(socket, gq: q, gresults: Search.run(socket.assigns.all_wikis, q))}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    snap = Scanner.snapshot()
    wiki = Enum.find(snap.wikis, &(&1.name == params["wiki"]))
    socket = assign(socket, all_wikis: snap.wikis, ts: snap.ts)

    socket =
      cond do
        is_nil(wiki) ->
          assign(socket,
            mode: :missing,
            wiki: nil,
            wiki_name: params["wiki"],
            page: nil,
            page_id: nil,
            html: nil,
            backlinks: []
          )

        params["page"] ->
          case Reader.render_page(wiki, params["page"]) do
            {:ok, page, html, backlinks} ->
              assign(socket,
                mode: :page,
                wiki: wiki,
                page: page,
                page_id: page.id,
                html: html,
                backlinks: backlinks,
                page_title: page.title
              )

            :error ->
              assign(socket,
                mode: :missing_page,
                wiki: wiki,
                page: nil,
                page_id: params["page"],
                html: nil,
                backlinks: []
              )
          end

        true ->
          assign(socket,
            mode: :list,
            wiki: wiki,
            page: nil,
            page_id: nil,
            html: nil,
            backlinks: [],
            page_title: wiki.name
          )
      end

    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.hub_shell
      view="reader"
      wikis={@all_wikis}
      active_wiki={@wiki && @wiki.name}
      ts={@ts}
      q={@gq}
      results={@gresults}
    >
      <nav class="breadcrumbs">
        <.link navigate={~p"/"}>Hub</.link>
        <%= if @wiki do %>
          / <.link navigate={~p"/r/#{@wiki.name}"}>{@wiki.name}</.link>
        <% end %>
        <%= if @page_id do %>
          / {@page_id}
        <% end %>
      </nav>

      <%= case @mode do %>
        <% :missing -> %>
          <p class="muted">No wiki named “{@wiki_name}”.</p>
        <% :missing_page -> %>
          <p class="muted">No page “{@page_id}” in {@wiki.name}.</p>
        <% :list -> %>
          <h1 class="wiki-h1">
            {@wiki.name} <span class="label">{@wiki.dialect}</span>
            <.link navigate={~p"/g/#{@wiki.name}"} class="small">· floor plan →</.link>
          </h1>
          <p :if={@wiki.working} class="working-line">▸ {@wiki.working}</p>
          <p :if={@wiki.pages == []} class="muted">No pages yet.</p>
          <form :if={@wiki.pages != []} phx-change="search" phx-submit="search" class="list-search">
            <input
              type="text"
              name="q"
              value={@q}
              class="search-input"
              placeholder={"Filter #{@wiki.name}…"}
              autocomplete="off"
              phx-debounce="120"
            />
          </form>
          <%= if String.trim(@q) == "" do %>
            <div class="grps">
              <section
                :for={
                  {cat, pages} <-
                    Enum.sort_by(Enum.group_by(@wiki.pages, & &1.category), &elem(&1, 0))
                }
                class="grp"
              >
                <h2>{cat} <span class="muted">{length(pages)}</span></h2>
                <ul>
                  <li :for={p <- Enum.sort_by(pages, & &1.id)}>
                    <.link navigate={~p"/r/#{@wiki.name}/#{p.id}"}>{p.title}</.link>
                    <span class="muted small">· {p.id}</span>
                  </li>
                </ul>
              </section>
            </div>
          <% else %>
            <% hits = filter_pages(@wiki.pages, @q) %>
            <ul class="hits">
              <li :for={p <- hits}>
                <.link navigate={~p"/r/#{@wiki.name}/#{p.id}"}>{p.title}</.link>
                <span class="muted small">· {p.category} / {p.id}</span>
                <div :if={p.excerpt not in [nil, ""]} class="excerpt">{p.excerpt}</div>
              </li>
              <li :if={hits == []} class="muted">No pages match “{String.trim(@q)}”.</li>
            </ul>
          <% end %>
        <% :page -> %>
          <% {prev, nxt} = neighbors(@wiki, @page) %>
          <nav class="reader-subnav">
            <.link navigate={~p"/r/#{@wiki.name}"}>← {@wiki.name}</.link>
            <span class="label">{@page.category}</span>
            <span class="spacer"></span>
            <.link :if={prev} navigate={~p"/r/#{@wiki.name}/#{prev.id}"} class="muted">
              ← {prev.title}
            </.link>
            <.link :if={nxt} navigate={~p"/r/#{@wiki.name}/#{nxt.id}"} class="muted">
              {nxt.title} →
            </.link>
          </nav>
          <article class="article">
            <div class="content">
              {raw(@html)}
            </div>
            <%= if @page.refs == [] and @backlinks == [] do %>
              <p class="orphan-hint">No links yet — this page is an orphan.</p>
            <% else %>
              <div class="refs">
                <div :if={@page.refs != []} class="refs-box">
                  <b>Links to</b>
                  <.link :for={r <- @page.refs} navigate={~p"/r/#{@wiki.name}/#{r}"}>{r}</.link>
                </div>
                <div :if={@backlinks != []} class="refs-box">
                  <b>Backlinks</b>
                  <.link :for={b <- @backlinks} navigate={~p"/r/#{@wiki.name}/#{b}"}>{b}</.link>
                </div>
              </div>
            <% end %>
          </article>
      <% end %>
    </.hub_shell>
    """
  end

  # Prev/next within the same category, ordered by id.
  defp neighbors(wiki, page) do
    siblings = wiki.pages |> Enum.filter(&(&1.category == page.category)) |> Enum.sort_by(& &1.id)

    case Enum.find_index(siblings, &(&1.id == page.id)) do
      nil -> {nil, nil}
      i -> {if(i > 0, do: Enum.at(siblings, i - 1)), Enum.at(siblings, i + 1)}
    end
  end

  # In-wiki page search over title, id, category and the body preview.
  defp filter_pages(pages, q) do
    needle = q |> String.trim() |> String.downcase()

    pages
    |> Enum.filter(fn p ->
      "#{p.title} #{p.id} #{p.category} #{p.excerpt}"
      |> String.downcase()
      |> String.contains?(needle)
    end)
    |> Enum.sort_by(& &1.id)
  end
end
