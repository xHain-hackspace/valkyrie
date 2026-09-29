defmodule Valkyrie do
  @moduledoc """
  Valkyrie keeps the contexts that define your domain
  and business logic.

  Contexts are also responsible for managing your data, regardless
  if it comes from the database, an external API or others.
  """

  @doc """
  Returns the running application version, derived from the git tag at build
  time (see `version/0` in `mix.exs`).
  """
  def version, do: :valkyrie |> Application.spec(:vsn) |> to_string()
end
