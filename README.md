# Wikihub

A local hub for all your Markdown wikis. Point it at your notes and it gives you
one cross-wiki **dashboard**, a clean **reader**, a 3D **mind-palace map**, and
**search** — and it refreshes itself the moment you (or anything else) change a
file on disk.

Wikihub never modifies your notes. It reads `.md` files and serves a UI; your
files stay exactly where they are, in whatever editor or tool you already use.

---

## What it does

Every page shares a **masthead** (wordmark + global search + live counts) and a
**wiki sidebar**, so you can jump between wikis or search from anywhere.

- **Dashboard** (`/`) — a health strip (attention, broken refs, orphans,
  unsourced, wikis, pages) over a **sortable table** of every wiki (click a
  column to sort; click a stat to filter), plus panels for attention, recent
  activity, a content map, and link health.
- **Reader** (`/r/:wiki`) — browse a wiki's pages by category, open a page as
  rendered HTML with a sticky sub-nav (prev/next within the category), and follow
  its links and **backlinks**. `[[wikilinks]]` and relative `*.md` links are
  rewritten so navigation works in the browser.
- **Map** (`/g/:wiki`) — a **3D mind palace** (WebGL/three.js): each folder is a
  walled room on a floor plan, each note is a placard *standing where it lives on
  disk*, and **show connections** draws cross-reference corridors across the floor
  (hover a note to light its links). Drag to orbit, scroll to zoom, search to fly
  to a note, click a placard to read it. Falls back to a 2D plan without WebGL.
- **Search** — the masthead box searches **across all wikis** (press `/` or
  `⌘/Ctrl-K` to focus, arrows + Enter to open a result); the reader also has a
  per-wiki filter. Both match page titles, ids, categories, and a body preview,
  and update as you type.
- **Live updates** — a file watcher plus a periodic rescan keep every open page
  in sync within a couple of seconds. No refresh needed.

The interface is deliberately flat and sharp (Swiss/editorial): hairline rules
and type, a single accent colour, and no rounded corners.

---

## Quick start

Prerequisites: **Elixir ~> 1.15** and **Erlang/OTP** (e.g. `brew install elixir`).

```bash
mix setup          # fetch deps + build assets
mix phx.server     # start the server
```

Open <http://localhost:4000>.

If you don't have any wikis yet, the dashboard tells you exactly where to put
one. The fastest way to see Wikihub working:

```bash
mkdir -p ~/notes/wiki/pages/ideas
echo "# Hello\nMy first wiki page." > ~/notes/wiki/pages/ideas/hello.md
```

The dashboard updates on its own — a **notes** wiki appears with one page.

---

## Where your wikis live

By default Wikihub scans `~/<project>/wiki` — i.e. any directory named `wiki`
directly inside a folder in your home directory. That wiki is named after its
parent (`~/research/wiki` → **research**).

Keep your notes somewhere else? Set **`WIKIHUB_PATHS`** to one or more
comma-separated paths or globs:

```bash
# a single folder of notes
WIKIHUB_PATHS=~/Documents/notes mix phx.server

# several locations / globs
WIKIHUB_PATHS="~/notes,~/work/*/wiki" mix phx.server
```

Each matched directory becomes a wiki, named after its own folder — except the
`<project>/wiki` convention above, where it takes the project name. Hidden
(dotfile) directories are included.

---

## Wiki structures

Wikihub auto-detects one of two layouts per wiki, based on whether the wiki has
a `pages/` subdirectory. Both are plain folders of Markdown — pick whichever
you already use.

### `pages` — a hierarchical wiki

A `pages/` tree where the first folder under `pages/` is the page's **category**.
Links are declared in frontmatter and/or as `[[wikilinks]]`.

```
~/research/wiki/
  pages/
    concepts/some-concept.md         # category: concepts
    entities/some-entity.md          # category: entities
  log.md                             # optional, see below
  WORKING.md                         # optional, see below
```

```markdown
---
title: A concept note
refs: [some-entity]
sources: [a-source]
last_modified: 2026-05-28
---

# A concept note
How this idea connects to others. See [[some-entity]].
```

### `obsidian` — topic folders

No `pages/` directory; instead each **top-level folder is a category** and its
`.md` files are pages. Works with an Obsidian vault. `raw/`, `.obsidian/`,
`.git/`, and `_overview.md` files are ignored.

```
~/notes/wiki/
  atomic/some-note.md                # category: atomic
  research/another-note.md           # category: research
  index.md
```

```markdown
---
type: wiki-page
topic: atomic
updated: 2026-04-09
sources: [phase-1-results]
---

# Some note
Links to [[research/another-note|Another note]].
```

The tag on each dashboard card (`pages` / `obsidian`) tells you how a wiki was
detected.

---

## Frontmatter keys

Frontmatter is optional YAML between `---` fences. Wikihub reads:

| Key | Purpose |
| --- | --- |
| `title` | Page title (falls back to the filename) |
| `refs` | Outgoing links — page ids (list or inline `[a, b]`). `[[wikilinks]]` in the body count too |
| `sources` | Citations; a page with none is flagged "unsourced" |
| `last_modified` / `updated` / `created` | Page date (ISO `YYYY-MM-DD`); falls back to file modification time |

Page **id** is the filename without `.md`. Links resolve by id within the same
wiki.

---

## Optional files

These live at the wiki root and power dashboard panels — all optional:

- **`log.md`** — an activity feed. Lines shaped like
  `## [2026-05-28] init | created the wiki` become "recent activity" entries
  (date · operation · title).
- **`WORKING.md`** — the first non-heading line is shown atop the wiki's reader
  page as its current focus (`▸ …`).

---

## Freshness & link health

- **Freshness dot** — based on the newest page/file date: ● fresh (≤7 days),
  ◐ aging (≤14 days), ○ stale (>14 days), · empty.
- **Attention panel** — stub or non-fresh wikis, oldest first.
- **Links & health** — *orphans* (pages nothing links to), *broken refs*
  (links to ids that don't exist in that wiki), and *unsourced* pages.

---

## Live updates

Wikihub watches the discovered directories and rescans (debounced) on any
change, and re-discovers new wikis on a 60-second timer. Changes broadcast over
Phoenix PubSub, so the dashboard, reader, and graph update live — whether you
edited a file by hand, in Obsidian, or via a script.

---

## Configuration reference

All optional. Set them as environment variables when starting the server.

| Variable | Default | Meaning |
| --- | --- | --- |
| `WIKIHUB_PATHS` | `~/*/wiki` | Comma-separated paths or globs to scan for wikis |
| `WIKIHUB_IGNORE` | *(none)* | Comma-separated wiki names to hide from the hub |
| `PORT` | `4000` | HTTP port |

```bash
WIKIHUB_PATHS="~/notes,~/work/*/wiki" WIKIHUB_IGNORE="scratch" PORT=4040 mix phx.server
```

---

## Troubleshooting

- **"No wikis found."** Nothing matched `WIKIHUB_PATHS` (or the default
  `~/*/wiki`). Check the path, and that it contains `.md` files. The dashboard's
  empty state shows an example layout.
- **A wiki is missing.** Confirm its directory matches your `WIKIHUB_PATHS` and
  isn't listed in `WIKIHUB_IGNORE`.
- **Port already in use.** Start with a different `PORT`, e.g.
  `PORT=4040 mix phx.server`.
- **The map is blank.** It needs a WebGL-capable browser; if WebGL is
  unavailable it falls back to a 2D floor plan.

---

## How it fits together

| File | Responsibility |
| --- | --- |
| `lib/wikihub/parser.ex` | Discover wikis, parse pages, build the link graph |
| `lib/wikihub/scanner.ex` | Hold the parsed model in memory; rescan + broadcast |
| `lib/wikihub/watcher.ex` | Watch wiki directories for file changes |
| `lib/wikihub/frontmatter.ex` | Tiny dependency-free YAML frontmatter reader |
| `lib/wikihub/panels.ex` | Aggregate wikis into dashboard panels |
| `lib/wikihub/reader.ex` | Render a page to HTML; rewrite links; compute backlinks |
| `lib/wikihub_web/live/*` | Dashboard, reader, and graph LiveViews |
