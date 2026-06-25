defmodule WikihubWeb.Router do
  use WikihubWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {WikihubWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  scope "/", WikihubWeb do
    pipe_through :browser

    live_session :default do
      live "/", DashboardLive, :index
      live "/r/:wiki", ReaderLive, :wiki
      live "/r/:wiki/:page", ReaderLive, :page
      live "/g/:wiki", GraphLive, :graph
    end
  end
end
