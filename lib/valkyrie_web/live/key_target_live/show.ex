defmodule ValkyrieWeb.KeyTargetLive.Show do
  use ValkyrieWeb, :live_view

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user}>
      <.header>
        Door: {@key_target.name}
        <:subtitle>Served at <code>/authorized_keys/{@key_target.slug}</code>.</:subtitle>

        <:actions>
          <.button_link navigate={~p"/doors"}>
            <.icon name="hero-arrow-left" /> Back
          </.button_link>
          <.button_link navigate={~p"/doors/#{@key_target}/edit?return_to=show"}>
            <.icon name="hero-pencil-square" /> Edit Door
          </.button_link>
        </:actions>
      </.header>

      <.list>
        <:item title="Slug">{@key_target.slug}</:item>

        <:item title="Name">{@key_target.name}</:item>
      </.list>
    </Layouts.app>
    """
  end

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Show Door")
     |> assign(
       :key_target,
       Ash.get!(Valkyrie.Members.KeyTarget, id, actor: socket.assigns.current_user)
     )}
  end
end
