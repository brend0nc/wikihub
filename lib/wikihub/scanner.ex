defmodule Wikihub.Scanner do
  @moduledoc """
  Holds the parsed model in memory and rebuilds it on demand. Coalesces bursts
  of file events into a single rescan, rediscovers new wikis on a timer, and
  broadcasts `:updated` over PubSub so LiveViews refresh.
  """
  use GenServer
  alias Wikihub.{Parser, Panels}

  @topic "wikis"
  @rediscover_ms 60_000
  @debounce_ms 300

  def start_link(_), do: GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  def snapshot, do: GenServer.call(__MODULE__, :snapshot)
  def rescan, do: GenServer.cast(__MODULE__, :rescan)
  def topic, do: @topic

  @impl true
  def init(:ok) do
    Process.send_after(self(), :rediscover, @rediscover_ms)
    {:ok, build()}
  end

  @impl true
  def handle_call(:snapshot, _from, state), do: {:reply, state, state}

  @impl true
  def handle_cast(:rescan, %{pending: true} = state), do: {:noreply, state}

  def handle_cast(:rescan, state) do
    Process.send_after(self(), :do_rescan, @debounce_ms)
    {:noreply, %{state | pending: true}}
  end

  @impl true
  def handle_info(:do_rescan, _state), do: {:noreply, rebuild()}

  def handle_info(:rediscover, _state) do
    Process.send_after(self(), :rediscover, @rediscover_ms)
    {:noreply, rebuild()}
  end

  defp rebuild do
    state = build()
    Phoenix.PubSub.broadcast(Wikihub.PubSub, @topic, :updated)
    state
  end

  defp build do
    wikis = Parser.scan()
    %{wikis: wikis, panels: Panels.build(wikis), pending: false, ts: DateTime.utc_now()}
  end
end
