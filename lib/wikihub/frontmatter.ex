defmodule Wikihub.Frontmatter do
  @moduledoc """
  Minimal YAML-frontmatter reader — no dependency. Handles `key: scalar`,
  inline lists `key: [a, b]`, and block lists (`- item` on following lines),
  which is all the two wiki dialects use.
  """

  @spec parse(binary) :: {map, binary}
  def parse("---\n" <> rest) do
    case String.split(rest, ~r/\n---\s*\n/, parts: 2) do
      [yaml, body] -> {parse_yaml(yaml), body}
      [_] -> {%{}, "---\n" <> rest}
    end
  end

  def parse(content), do: {%{}, content}

  defp parse_yaml(yaml) do
    {map, _last} =
      yaml
      |> String.split("\n")
      |> Enum.reduce({%{}, nil}, fn raw, {acc, last} ->
        line = String.trim_trailing(raw)
        trimmed = String.trim(line)

        cond do
          trimmed == "" or String.starts_with?(trimmed, "#") ->
            {acc, last}

          String.starts_with?(trimmed, "- ") and last != nil ->
            item = trimmed |> String.trim_leading("- ") |> clean()

            {Map.update(acc, last, [item], fn
               v when is_list(v) -> v ++ [item]
               v -> [v, item]
             end), last}

          true ->
            case String.split(line, ":", parts: 2) do
              [k, v] ->
                key = String.trim(k)
                val = String.trim(v)

                if val == "" do
                  {Map.put_new(acc, key, []), key}
                else
                  {Map.put(acc, key, parse_val(val)), key}
                end

              [_] ->
                {acc, last}
            end
        end
      end)

    map
  end

  defp parse_val("[" <> _ = v) do
    v
    |> String.trim_leading("[")
    |> String.trim_trailing("]")
    |> String.split(",")
    |> Enum.map(&clean/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp parse_val(v), do: clean(v)

  defp clean(s), do: s |> String.trim() |> String.trim("\"") |> String.trim("'")
end
