defmodule Valkyrie.Members.Stats do
  @moduledoc """
  Periodic measurements about the member population, emitted via telemetry
  and surfaced as Prometheus metrics by `ValkyrieWeb.Telemetry`.
  """

  require Ash.Query

  alias Valkyrie.Members.Member
  alias Valkyrie.Members.KeyTargets
  alias Valkyrie.Members.KeyTarget
  require Logger

  def emit_member_counts do
    total = Ash.count!(Member, authorize?: false)

    keyholder_count =
      Member
      |> Ash.Query.filter(exists(key_target_accesses, true))
      |> Ash.count!(authorize?: false)

    :telemetry.execute([:valkyrie, :members, :total], %{count: total}, %{})

    :telemetry.execute([:valkyrie, :members, :keyholders], %{count: keyholder_count}, %{
      target: "all"
    })

    for %KeyTarget{} = key_target <- KeyTargets.all() do
      target_key_holder_count =
        Member
        |> Ash.Query.filter(exists(key_target_accesses, key_target_id == ^key_target.id))
        |> Ash.count!(authorize?: false)

      :telemetry.execute(
        [:valkyrie, :members, :keyholders],
        %{count: target_key_holder_count},
        %{target: key_target.slug}
      )
    end

    :ok
  end
end
