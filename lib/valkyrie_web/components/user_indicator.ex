defmodule ValkyrieWeb.Components.UserIndicator do
  @moduledoc """
  Top-bar indicator for the signed-in user: a user icon plus the current role.

  Kept as its own component so it can grow (username, account dropdown,
  sign-out, ...) without touching the layout.
  """
  use ValkyrieWeb, :html

  @doc """
  Renders the current user's role next to a user icon.

  Renders nothing when there is no signed-in user.
  """
  attr :current_user, :map, default: nil, doc: "the signed-in user, or nil"
  attr :class, :string, default: nil, doc: "extra classes for the wrapper"

  def user_indicator(assigns) do
    ~H"""
    <div
      :if={@current_user}
      class={["flex items-center gap-2", @class]}
      title={"Signed in — role: #{role_label(@current_user)}"}
    >
      <.tooltip text={role_label(@current_user)} position="bottom">
        <:trigger>
          <.icon name="hero-user-circle" class="size-6" />
          <span class="text-sm font-medium">{user_name(@current_user)}</span>
        </:trigger>
      </.tooltip>
    </div>
    """
  end

  defp role_label(%{is_admin: true}), do: "Admin"
  defp role_label(_user), do: "User"
  defp user_name(%{username: username}), do: username
end
