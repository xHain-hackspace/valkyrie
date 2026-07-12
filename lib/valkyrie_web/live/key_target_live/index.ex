defmodule ValkyrieWeb.KeyTargetLive.Index do
  use ValkyrieWeb, :live_view

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user}>
      <.header>
        Doors
        <:actions>
          <.button_link navigate={~p"/doors/new"}>
            <.icon name="hero-plus" /> New Door
          </.button_link>
        </:actions>
      </.header>

      <.table
        id="key_targets"
        rows={@streams.key_targets}
        thead_class="text-lg font-extrabold"
        rounded="large"
      >
        <:col :let={{_id, key_target}} label="Slug">{key_target.slug}</:col>

        <:col :let={{_id, key_target}} label="Name">{key_target.name}</:col>

        <:action :let={{id, key_target}}>
          <.button_link navigate={~p"/doors/#{key_target}/edit"}>Edit</.button_link>
          <.button
            phx-click={JS.push("delete", value: %{id: key_target.id}) |> hide("##{id}")}
            data-confirm="Are you sure?"
          >
            Delete
          </.button>
        </:action>
      </.table>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Doors")
     |> assign_new(:current_user, fn -> nil end)
     |> stream(
       :key_targets,
       Ash.read!(Valkyrie.Members.KeyTarget, actor: socket.assigns[:current_user])
     )}
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    key_target = Ash.get!(Valkyrie.Members.KeyTarget, id, actor: socket.assigns.current_user)
    Ash.destroy!(key_target, actor: socket.assigns.current_user)

    {:noreply, stream_delete(socket, :key_targets, key_target)}
  end
end
