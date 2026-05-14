defmodule Valkyrie.Members.Stats do
  @moduledoc """
  Periodic measurements about the member population, emitted via telemetry
  and surfaced as Prometheus metrics by `ValkyrieWeb.Telemetry`.
  """

  require Ash.Query

  alias Valkyrie.Members.Member

  def emit_member_counts do
    members = Member |> Ash.read!(authorize?: false)

    keyholders = Enum.count(members, & &1.has_key)

    :telemetry.execute([:valkyrie, :members, :total], %{count: length(members)}, %{})
    :telemetry.execute([:valkyrie, :members, :keyholders], %{count: keyholders}, %{})

    :ok
  end
end
