defmodule ValkyrieWeb.KeyTargetLive.Form do
  use ValkyrieWeb, :live_view

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user}>
      <.header>
        {@page_title}
        <:subtitle>
          A door is a key access target served at <code>/authorized_keys/&lt;slug&gt;</code>.
        </:subtitle>
      </.header>

      <.form
        for={@form}
        id="key_target-form"
        phx-change="validate"
        phx-submit="save"
      >
        <%= if @form.source.type == :create do %>
          <.input field={@form[:slug]} type="text" label="Slug" />
          <.input field={@form[:name]} type="text" label="Name" />
          <.input
            field={@form[:grant_to_all_keyholders]}
            type="checkbox"
            label="Grant access to all current keyholders"
          />
        <% end %>
        <%= if @form.source.type == :update do %>
          <%!-- Slug is immutable (natural key + URL identity); only the name is editable. --%>
          <.input field={@form[:name]} type="text" label="Name" />
        <% end %>

        <.input_button type="submit" value="Save" />
        <.button_link navigate={return_path(@return_to, @key_target)}>Cancel</.button_link>
      </.form>
    </Layouts.app>
    """
  end

  @impl true
  def mount(params, _session, socket) do
    key_target =
      case params["id"] do
        nil -> nil
        id -> Ash.get!(Valkyrie.Members.KeyTarget, id, actor: socket.assigns.current_user)
      end

    action = if is_nil(key_target), do: "New", else: "Edit"
    page_title = action <> " Door"

    {:ok,
     socket
     |> assign(:return_to, return_to(params["return_to"]))
     |> assign(key_target: key_target)
     |> assign(:page_title, page_title)
     |> assign_form()}
  end

  defp return_to("show"), do: "show"
  defp return_to(_), do: "index"

  @impl true
  def handle_event("validate", %{"key_target" => key_target_params}, socket) do
    {:noreply,
     assign(socket, form: AshPhoenix.Form.validate(socket.assigns.form, key_target_params))}
  end

  def handle_event("save", %{"key_target" => key_target_params}, socket) do
    case AshPhoenix.Form.submit(socket.assigns.form, params: key_target_params) do
      {:ok, key_target} ->
        socket =
          socket
          |> put_flash(:info, "Door #{socket.assigns.form.source.type}d successfully")
          |> push_navigate(to: return_path(socket.assigns.return_to, key_target))

        {:noreply, socket}

      {:error, form} ->
        {:noreply, assign(socket, form: form)}
    end
  end

  defp assign_form(%{assigns: %{key_target: key_target}} = socket) do
    form =
      if key_target do
        AshPhoenix.Form.for_update(key_target, :update,
          as: "key_target",
          actor: socket.assigns.current_user
        )
      else
        AshPhoenix.Form.for_create(Valkyrie.Members.KeyTarget, :create,
          as: "key_target",
          actor: socket.assigns.current_user
        )
        # Seed the "grant to all keyholders" checkbox so it renders checked by
        # default, matching the create action's `grant_to_all_keyholders` default.
        |> AshPhoenix.Form.validate(%{"grant_to_all_keyholders" => "true"})
      end

    assign(socket, form: to_form(form))
  end

  defp return_path("index", _key_target), do: ~p"/doors"
  defp return_path("show", key_target), do: ~p"/doors/#{key_target.id}"
end
