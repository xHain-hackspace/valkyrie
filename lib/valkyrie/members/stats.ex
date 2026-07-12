defmodule Valkyrie.Members.Stats do
  @moduledoc """
  Periodic measurements about the member population, emitted via telemetry
  and surfaced as Prometheus metrics by `ValkyrieWeb.Telemetry`.
  """

  require Ash.Query

  alias Valkyrie.Members.Member
  alias Valkyrie.Members.KeyTargets
  alias Valkyrie.Members.KeyTarget

  def emit_member_counts do
    members = Member |> Ash.read!(authorize?: false)

    keyholder_count = Enum.count(members, &Member.keyholder?/1)

    :telemetry.execute([:valkyrie, :members, :total], %{count: length(members)}, %{})

    :telemetry.execute([:valkyrie, :members, :keyholders], %{count: keyholder_count}, %{
      target: "all"
    })

    for %KeyTarget{} = key_target <- KeyTargets.all() do
      target_key_holders = Enum.count(members, fn m -> Member.keyholder?(m, key_target.slug) end)

      :telemetry.execute(
        [:valkyrie, :members, :keyholders],
        %{count: target_key_holders},
        %{target: key_target.slug}
      )
    end

    :ok
  end
end
