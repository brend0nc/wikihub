defmodule WikihubWeb.DashboardLive do
  @moduledoc "The cross-wiki dashboard. Subscribes to Scanner updates and re-renders live."
  use WikihubWeb, :live_view
  alias Wikihub.{Scanner, Search}

  @filter_keys %{"attention" => :attention, "orphans" => :orphans, "broken" => :broken}

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: Phoenix.PubSub.subscribe(Wikihub.PubSub, Scanner.topic())

    socket =
      socket
      |> assign(gq: "", gresults: nil, sort: {:attention, :asc}, filters: MapSet.new())
      |> assign_snapshot()

    {:ok, socket}
  end

  @impl true
  def handle_info(:updated, socket), do: {:noreply, assign_snapshot(socket)}

  @impl true
  def handle_event("global_search", %{"q" => q}, socket) do
    {:noreply, assign(socket, gq: q, gresults: Search.run(socket.assigns.wikis, q))}
  end

  def handle_event("sort", %{"key" => key}, socket) do
    new = String.to_existing_atom(key)
    {cur, dir} = socket.assigns.sort
    sort = if cur == new, do: {new, flip(dir)}, else: {new, :asc}
    {:noreply, assign(socket, sort: sort)}
  end

  def handle_event("filter", %{"name" => name}, socket) do
    case @filter_keys[name] do
      nil -> {:noreply, socket}
      key -> {:noreply, assign(socket, filters: toggle(socket.assigns.filters, key))}
    end
  end

  def handle_event("clear_filters", _params, socket) do
    {:noreply, assign(socket, filters: MapSet.new())}
  end

  defp assign_snapshot(socket) do
    s = Scanner.snapshot()
    assign(socket, page_title: "Wiki Hub", wikis: s.wikis, panels: s.panels, ts: s.ts)
  end

  @impl true
  def render(assigns) do
    assigns = assign(assigns, rows: rows(assigns.wikis, assigns.filters, assigns.sort))

    ~H"""
    <.hub_shell view="dashboard" wikis={@wikis} ts={@ts} q={@gq} results={@gresults}>
      <%= if @wikis == [] do %>
        <article class="empty">
          <h2>Add your first wiki</h2>
          <p>
            Wikihub scans <code>~/&lt;project&gt;/wiki</code>
            for Markdown wikis. Create one, or point <code>WIKIHUB_PATHS</code>
            at where your notes already live — this page refreshes the
            moment a file changes.
          </p>
          <pre>{"~/notes/wiki/\n  log.md\n  pages/\n    ideas/first-note.md"}</pre>
          <div class="copy-block">
            <code id="onboard-cmd">WIKIHUB_PATHS=~/Documents/notes mix phx.server</code>
            <button class="copy-btn" phx-hook="Copy" id="copy-cmd" data-copy-target="#onboard-cmd">
              copy
            </button>
          </div>
        </article>
      <% else %>
        <section class="kpi-strip">
          <button
            class={["kpi", "is-action", filter_on?(@filters, :attention) && "is-on"]}
            phx-click="filter"
            phx-value-name="attention"
          >
            <b class="kpi-n">{attention_count(@wikis)}</b><span class="kpi-l">attention</span>
          </button>
          <button
            class={["kpi", "warn", "is-action", filter_on?(@filters, :broken) && "is-on"]}
            phx-click="filter"
            phx-value-name="broken"
          >
            <b class="kpi-n">{length(@panels.broken)}</b><span class="kpi-l">broken refs</span>
          </button>
          <button
            class={["kpi", "is-action", filter_on?(@filters, :orphans) && "is-on"]}
            phx-click="filter"
            phx-value-name="orphans"
          >
            <b class="kpi-n">{length(@panels.orphans)}</b><span class="kpi-l">orphans</span>
          </button>
          <div class="kpi">
            <b class="kpi-n">{@panels.unsourced_count}</b><span class="kpi-l">unsourced</span>
          </div>
          <div class="kpi"><b class="kpi-n">{length(@wikis)}</b><span class="kpi-l">wikis</span></div>
          <div class="kpi">
            <b class="kpi-n">{@panels.total_pages}</b><span class="kpi-l">pages</span>
          </div>
        </section>

        <div :if={MapSet.size(@filters) > 0} class="chip-bar">
          <span class="muted small">filtering:</span>
          <button
            :for={f <- @filters}
            class="chip is-on"
            phx-click="filter"
            phx-value-name={Atom.to_string(f)}
          >
            {f} ✕
          </button>
          <button class="chip-reset" phx-click="clear_filters">clear</button>
        </div>

        <table class="wiki-table">
          <thead>
            <tr>
              <th></th>
              <th phx-click="sort" phx-value-key="name" class={th_cls(@sort, :name)}>
                Wiki {chev(@sort, :name)}
              </th>
              <th phx-click="sort" phx-value-key="dialect" class={th_cls(@sort, :dialect)}>
                Type {chev(@sort, :dialect)}
              </th>
              <th phx-click="sort" phx-value-key="pages" class={["num", th_cls(@sort, :pages)]}>
                Pages {chev(@sort, :pages)}
              </th>
              <th phx-click="sort" phx-value-key="activity" class={th_cls(@sort, :activity)}>
                Last activity {chev(@sort, :activity)}
              </th>
              <th class="cell-cats">Categories</th>
              <th phx-click="sort" phx-value-key="orphans" class={["num", th_cls(@sort, :orphans)]}>
                Orphans {chev(@sort, :orphans)}
              </th>
              <th phx-click="sort" phx-value-key="broken" class={["num", th_cls(@sort, :broken)]}>
                Broken {chev(@sort, :broken)}
              </th>
            </tr>
          </thead>
          <tbody>
            <tr :for={w <- @rows} class={w.stub && "is-stub"}>
              <td><span class={"dot #{w.bucket}"}>{dot_char(w.bucket)}</span></td>
              <td><.link navigate={~p"/r/#{w.name}"} class="wname">{w.name}</.link></td>
              <td>{w.dialect}</td>
              <td class="num">{length(w.pages)}</td>
              <td>{ago(w.last_activity)}</td>
              <td class="cell-cats">{cats_label(w)}</td>
              <td class={["num", w.orphans != [] && "has"]}>{length(w.orphans)}</td>
              <td class={["num", w.broken_refs != [] && "warn"]}>{length(w.broken_refs)}</td>
            </tr>
            <tr :if={@rows == []}>
              <td colspan="8" class="muted">No wikis match these filters.</td>
            </tr>
          </tbody>
        </table>

        <div class="panels">
          <section class="panel">
            <h2>Attention</h2>
            <ul>
              <li :for={w <- attention(@wikis)}>
                <span class={"dot #{w.bucket}"}>{dot_char(w.bucket)}</span>
                {w.name} — {ago(w.last_activity)}
                <span :if={stale_count(w) > 0} class="muted">· {stale_count(w)} stale pages</span>
              </li>
              <li :if={attention(@wikis) == []} class="muted">all wikis fresh</li>
            </ul>
          </section>

          <section class="panel">
            <h2>Recent activity</h2>
            <ul class="feed">
              <li :for={e <- @panels.feed}>
                <span class="muted">{e.date}</span>
                <span class="op">{e.op}</span>
                {e.title}
                <span class="muted">· {e.wiki}</span>
              </li>
              <li :if={@panels.feed == []} class="muted">no dated log entries</li>
            </ul>
            <h3>Recently changed</h3>
            <ul class="feed">
              <li :for={{name, id, date} <- @panels.recent_pages}>
                <span class="muted">{Date.to_string(date)}</span>
                <.link navigate={~p"/r/#{name}/#{id}"}>{id}</.link>
                <span class="muted">· {name}</span>
              </li>
            </ul>
          </section>

          <section class="panel">
            <h2>Content map</h2>
            <div :for={{name, cats} <- @panels.content_map} :if={map_size(cats) > 0} class="cmap">
              <b>{name}</b>
              <div>
                <span :for={{cat, n} <- Enum.sort(cats)} class="cbar">{cat} <i>{n}</i></span>
              </div>
            </div>
          </section>

          <section class="panel">
            <h2>Links &amp; health</h2>
            <div class="metrics">
              <span><b>{length(@panels.orphans)}</b> orphans</span>
              <span><b>{length(@panels.broken)}</b> broken refs</span>
              <span><b>{@panels.unsourced_count}</b> unsourced</span>
            </div>
            <ul class="small">
              <li :for={{wiki, id} <- Enum.take(@panels.orphans, 12)} class="muted">
                orphan · <.link navigate={~p"/r/#{wiki}/#{id}"}>{id}</.link> ({wiki})
              </li>
              <li :for={{wiki, from, to} <- Enum.take(@panels.broken, 8)} class="warn">
                broken · {from} → {to} ({wiki})
              </li>
            </ul>
          </section>
        </div>
      <% end %>
    </.hub_shell>
    """
  end

  # --- rows: filter + sort ---------------------------------------------------

  defp rows(wikis, filters, sort), do: wikis |> apply_filters(filters) |> sort_wikis(sort)

  defp apply_filters(wikis, filters) do
    Enum.filter(wikis, fn w -> Enum.all?(filters, &match_filter(w, &1)) end)
  end

  defp match_filter(w, :attention), do: w.stub or w.bucket in [:aging, :stale]
  defp match_filter(w, :orphans), do: w.orphans != []
  defp match_filter(w, :broken), do: w.broken_refs != []

  defp sort_wikis(wikis, {key, dir}), do: Enum.sort_by(wikis, &skey(&1, key), dir)

  defp skey(w, :name), do: w.name
  defp skey(w, :dialect), do: to_string(w.dialect)
  defp skey(w, :pages), do: length(w.pages)
  defp skey(w, :activity), do: gdays(w.last_activity)
  defp skey(w, :orphans), do: length(w.orphans)
  defp skey(w, :broken), do: length(w.broken_refs)
  defp skey(w, :attention), do: {att_rank(w), gdays(w.last_activity)}

  defp gdays(%Date{} = d), do: Date.to_gregorian_days(d)
  defp gdays(_), do: 0

  defp att_rank(%{stub: true}), do: 0
  defp att_rank(%{bucket: :stale}), do: 1
  defp att_rank(%{bucket: :aging}), do: 2
  defp att_rank(_), do: 3

  defp flip(:asc), do: :desc
  defp flip(:desc), do: :asc

  defp toggle(set, key) do
    if MapSet.member?(set, key), do: MapSet.delete(set, key), else: MapSet.put(set, key)
  end

  defp filter_on?(set, key), do: MapSet.member?(set, key)

  # --- view helpers ----------------------------------------------------------

  defp th_cls({cur, _}, key), do: cur == key && "is-sort"
  defp chev({cur, dir}, key) when cur == key, do: if(dir == :asc, do: "▲", else: "▼")
  defp chev(_, _), do: ""

  defp cats_label(w) do
    n = map_size(w.categories)
    if n == 0, do: "—", else: "#{n}"
  end

  defp attention_count(wikis), do: Enum.count(wikis, &(&1.stub or &1.bucket in [:aging, :stale]))

  defp dot_char(:fresh), do: "●"
  defp dot_char(:aging), do: "◐"
  defp dot_char(:stale), do: "○"
  defp dot_char(_), do: "·"

  defp ago(nil), do: "—"

  defp ago(date) do
    case Date.diff(Date.utc_today(), date) do
      n when n <= 0 -> "today"
      1 -> "1d ago"
      n -> "#{n}d ago"
    end
  end

  defp attention(wikis) do
    wikis
    |> Enum.filter(&(&1.stub or &1.bucket in [:aging, :stale]))
    |> Enum.sort_by(&(&1.last_activity || ~D[0001-01-01]), {:asc, Date})
  end

  defp stale_count(w), do: Enum.count(w.pages, &page_stale?/1)

  defp page_stale?(%{date: nil}), do: false
  defp page_stale?(%{date: d}), do: Date.diff(Date.utc_today(), d) > 14
end
