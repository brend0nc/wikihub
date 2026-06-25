defmodule Wikihub.Wiki do
  @moduledoc "One knowledge wiki on disk, parsed into a uniform shape."
  defstruct [
    :name,
    :path,
    :dialect,
    :pages,
    :categories,
    :log,
    :working,
    :last_activity,
    :bucket,
    :stub,
    :note,
    orphans: [],
    broken_refs: [],
    unsourced: []
  ]
end

defmodule Wikihub.Page do
  @moduledoc "One content page within a wiki."
  defstruct [
    :id,
    :wiki,
    :title,
    :category,
    :path,
    :date,
    :inbound,
    :excerpt,
    refs: [],
    sources: []
  ]
end
