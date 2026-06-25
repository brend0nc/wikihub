defmodule Wikihub.Watcher do
  @moduledoc """
  Watches the discovered wiki dirs and pokes the Scanner on any change, so edits
  (by Claude mid-session, by you in Obsidian, by anything) refresh the dashboard
  within seconds. New wikis are still picked up by the Scanner's rediscovery timer.
  """
  use GenServer
  alias Wikihub.{Parser, Scanner}

  def start_link(_), do: GenServer.start_link(__MODULE__, :ok, name: __MODULE__)

  @impl true
  def init(:ok) do
    case Parser.discover() do
      [] ->
        {:ok, %{pid: nil}}

      dirs ->
        case FileSystem.start_link(dirs: dirs) do
          {:ok, pid} ->
            FileSystem.subscribe(pid)
            {:ok, %{pid: pid}}

          _ ->
            {:ok, %{pid: nil}}
        end
    end
  end

  @impl true
  def handle_info({:file_event, _pid, {_path, _events}}, state) do
    Scanner.rescan()
    {:noreply, state}
  end

  def handle_info({:file_event, _pid, :stop}, state), do: {:noreply, state}
  def handle_info(_msg, state), do: {:noreply, state}
end
