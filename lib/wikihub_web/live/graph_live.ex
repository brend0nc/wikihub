defmodule WikihubWeb.GraphLive do
  @moduledoc """
  A spatial "mind-palace" floor plan of one wiki: folders are rooms (nested),
  pages are the notes stored in them, and refs are optional corridors. This is a
  map of *where each thing lives*, mirroring the room/door structure wikis use
  on disk (`_overview.md` per room, an `_door.md` index at the entrance).
  """
  use WikihubWeb, :live_view
  alias Wikihub.{Scanner, Search}

  @palette ~w(#4e79a7 #f28e2b #e15759 #76b7b2 #59a14f #edc948 #b07aa1 #ff9da7 #9c755f #bab0ac)

  @impl true
  def mount(_params, _session, socket), do: {:ok, assign(socket, gq: "", gresults: nil)}

  @impl true
  def handle_event("global_search", %{"q" => q}, socket) do
    {:noreply, assign(socket, gq: q, gresults: Search.run(socket.assigns.all_wikis, q))}
  end

  @impl true
  def handle_params(%{"wiki" => name}, _uri, socket) do
    snap = Scanner.snapshot()
    wiki = Enum.find(snap.wikis, &(&1.name == name))
    {tree, links, colors, rooms} = if wiki, do: build_map(wiki), else: {nil, "[]", %{}, "[]"}

    {:noreply,
     assign(socket,
       all_wikis: snap.wikis,
       ts: snap.ts,
       name: name,
       wiki: wiki,
       tree: tree,
       links: links,
       colors: colors,
       rooms: rooms,
       page_title: "#{name} map"
     )}
  end

  # --- build the room tree + corridor links ----------------------------------

  defp build_map(wiki) do
    tree = wiki.pages |> Enum.map(&{folder_segments(wiki, &1), &1}) |> build_tree()

    colors =
      tree.rooms
      |> Enum.map(& &1.name)
      |> Enum.with_index()
      |> Map.new(fn {n, i} -> {n, Enum.at(@palette, rem(i, length(@palette)))} end)

    ids = MapSet.new(wiki.pages, & &1.id)

    links =
      wiki.pages
      |> Enum.flat_map(fn p -> Enum.map(p.refs, &[p.id, &1]) end)
      |> Enum.filter(fn [_from, to] -> MapSet.member?(ids, to) end)
      |> Enum.uniq()

    {tree, Jason.encode!(links), colors, Jason.encode!(rooms_3d(wiki, colors))}
  end

  # Flattened-to-top-level rooms for the 3D scene; each note keeps its sub-folder.
  defp rooms_3d(wiki, colors) do
    wiki.pages
    |> Enum.group_by(fn p -> List.first(folder_segments(wiki, p)) || "·" end)
    |> Enum.map(fn {name, pages} ->
      %{
        name: name,
        color: colors[name] || "#9c755f",
        notes:
          pages
          |> Enum.sort_by(&{folder_segments(wiki, &1), &1.id})
          |> Enum.map(fn p ->
            %{
              id: p.id,
              title: p.title,
              sub: folder_segments(wiki, p) |> Enum.drop(1) |> Enum.join("/"),
              url: ~p"/r/#{wiki.name}/#{p.id}"
            }
          end)
      }
    end)
    |> Enum.sort_by(& &1.name)
  end

  defp folder_segments(wiki, page) do
    segs = page.path |> Path.relative_to(wiki.path) |> Path.split() |> Enum.drop(-1)
    if wiki.dialect == :pages, do: Enum.drop_while(segs, &(&1 == "pages")), else: segs
  end

  # Groups {segments, page} entries into nested %{name, rooms, items}.
  defp build_tree(entries) do
    {here, deeper} = Enum.split_with(entries, fn {segs, _} -> segs == [] end)

    rooms =
      deeper
      |> Enum.group_by(fn {segs, _} -> hd(segs) end)
      |> Enum.map(fn {name, group} ->
        group
        |> Enum.map(fn {segs, p} -> {tl(segs), p} end)
        |> build_tree()
        |> Map.put(:name, name)
      end)
      |> Enum.sort_by(& &1.name)

    %{rooms: rooms, items: here |> Enum.map(&elem(&1, 1)) |> Enum.sort_by(& &1.id)}
  end

  defp room_count(node), do: length(node.items) + Enum.sum(Enum.map(node.rooms, &room_count/1))

  # --- recursive room component ----------------------------------------------

  attr :node, :map, required: true
  attr :wiki, :string, required: true
  attr :color, :string, default: "#999"
  attr :depth, :integer, default: 0

  def room(assigns) do
    ~H"""
    <section class={"bp-room depth-#{@depth}"} style={"--room: #{@color}"}>
      <header class="bp-room-h">
        <span class="bp-room-name">{@node.name}</span>
        <span class="bp-room-n">{room_count(@node)}</span>
      </header>
      <div class="bp-room-body">
        <.room :for={sub <- @node.rooms} node={sub} wiki={@wiki} color={@color} depth={@depth + 1} />
        <.link
          :for={p <- @node.items}
          navigate={~p"/r/#{@wiki}/#{p.id}"}
          class="bp-tile"
          data-page-id={p.id}
          title={p.title}
        >
          {p.title}
        </.link>
      </div>
    </section>
    """
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.hub_shell
      view="graph"
      wikis={@all_wikis}
      active_wiki={@wiki && @name}
      ts={@ts}
      q={@gq}
      results={@gresults}
    >
      <nav class="breadcrumbs">
        <.link navigate={~p"/"}>Hub</.link>
        <%= if @wiki do %>
          / <.link navigate={~p"/r/#{@name}"}>{@name}</.link> / map
        <% end %>
      </nav>

      <%= if @wiki do %>
        <h1 class="wiki-h1">{@name} — floor plan</h1>
        <%= cond do %>
          <% @wiki.pages == [] -> %>
            <p class="muted">No notes yet — this room is empty.</p>
          <% true -> %>
            <p class="graph-hint">
              {length(@wiki.pages)} notes across {length(@tree.rooms)} rooms · folders are rooms, notes are what's stored in them · click a note to read it
            </p>
            <div class="graph-toolbar">
              <input
                class="graph-search"
                type="text"
                placeholder="Find a note…"
                data-bp-search
                autocomplete="off"
              />
              <label class="gbtn bp-toggle">
                <input type="checkbox" data-bp-links /> show connections
              </label>
              <button class="gbtn" data-bp-reset>Reset view</button>
              <span class="muted small bp-help">
                drag to orbit · scroll to zoom · click a note to read
              </span>
            </div>
            <div
              class="palace"
              id={"palace-#{@name}"}
              phx-hook="Palace"
              data-rooms={@rooms}
              data-links={@links}
            >
              <div class="palace-fallback">
                <div class="bp-door"><span>▢ entrance · {@name}</span></div>
                <div class="bp-rooms">
                  <.room :for={r <- @tree.rooms} node={r} wiki={@name} color={@colors[r.name]} />
                </div>
                <div :if={@tree.items != []} class="bp-loose">
                  <.link
                    :for={p <- @tree.items}
                    navigate={~p"/r/#{@name}/#{p.id}"}
                    class="bp-tile"
                    data-page-id={p.id}
                  >
                    {p.title}
                  </.link>
                </div>
              </div>
            </div>
        <% end %>
      <% else %>
        <p class="muted">No wiki named “{@name}”.</p>
      <% end %>
    </.hub_shell>
    """
  end
end
