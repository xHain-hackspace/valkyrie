defmodule Valkyrie.Versions.ChangeFormatter do
  @moduledoc """
  Turns a paper-trail `:full_diff` `changes` map into human-readable lines.

  Scalars arrive as `%{"from" => a, "to" => b}` (or just `%{"to" => v}` on create).
  Array attributes arrive as `%{"to" => [%{"added" => v}, %{"removed" => v},
  %{"unchanged" => v}]}`, rendered as an explicit "added ...; removed ..." summary.
  """

  @doc "Turn a full_diff `changes` map into a list of human-readable diff lines."
  def summarize(changes) do
    changes
    |> decode_changes()
    |> Enum.map(fn {key, value} -> format_change(key, value) end)
    |> Enum.reject(&(&1 == ""))
  end

  # Renders one papertrail change entry as a human-readable line, or "" when the
  # attribute is unchanged (so the caller can skip it).
  def format_change(_key, %{"unchanged" => _}), do: ""

  def format_change(key, %{"to" => elements}) when is_list(elements) do
    added = for %{"added" => v} <- elements, do: to_string(v)
    removed = for %{"removed" => v} <- elements, do: to_string(v)

    parts =
      [] ++
        if(added == [], do: [], else: ["added #{Enum.join(added, ", ")}"]) ++
        if(removed == [], do: [], else: ["removed #{Enum.join(removed, ", ")}"])

    case parts do
      [] -> ""
      _ -> "changed #{key}: #{Enum.join(parts, "; ")}"
    end
  end

  def format_change(key, %{"from" => from, "to" => to}) do
    "changed #{key} from #{format_audit_value(from)} to #{format_audit_value(to)}"
  end

  # A scalar set on create arrives as %{"to" => value} with no "from".
  def format_change(key, %{"to" => to}) do
    "changed #{key} from #{format_audit_value(nil)} to #{format_audit_value(to)}"
  end

  def format_change(_key, _value), do: ""

  # Renders a scalar papertrail value as a display string.
  defp format_audit_value(value) when value in [nil, ""], do: "<empty>"
  defp format_audit_value(value) when is_binary(value), do: value
  defp format_audit_value(value), do: inspect(value)

  @doc """
  Unwraps a single full_diff value envelope to its underlying value. A grant stores
  it under "to", a revoke under "unchanged", and scalar edits under "from"/"to".
  """
  def change_value(%{"to" => value}), do: value
  def change_value(%{"unchanged" => value}), do: value
  def change_value(%{"from" => value}), do: value
  def change_value(_), do: nil

  # SQLite stores JSON as TEXT, so `changes` may arrive as a string or a map.
  defp decode_changes(json) when is_binary(json), do: Jason.decode!(json)
  defp decode_changes(map) when is_map(map), do: map
  defp decode_changes(_), do: %{}
end
