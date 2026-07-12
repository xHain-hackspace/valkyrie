defmodule ValkyrieWeb.MemberLive.Form do
  require Logger
  use ValkyrieWeb, :live_view

  alias Valkyrie.Members.KeyTargets

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user}>
      <.header>
        {@page_title}
        <:subtitle>Use this form to manage member records in your database.</:subtitle>
      </.header>

      <.form
        for={@form}
        id="member-form"
        phx-change="validate"
        phx-submit="save"
      >
        <.input field={@form[:username]} type="text" label="Username" />
        <.input
          field={@form[:ssh_public_key]}
          type="text"
          label="SSH Public Key"
        />
        <.input field={@form[:tree_name]} type="text" label="Treename" />
        <%!-- Hidden field so deselecting all targets still submits an (empty) list. --%>
        <input type="hidden" name="member[key_targets][]" value="" />
        <.input
          field={@form[:key_targets]}
          type="select"
          multiple
          label="Key access targets"
          options={Enum.map(@key_targets, &{&1.name, &1.slug})}
        />

        <.input_button type="submit" value="Submit" />
        <.button_link navigate={return_path(@return_to, @member)}>Cancel</.button_link>
      </.form>
    </Layouts.app>
    """
  end

  @impl true
  def mount(params, _session, socket) do
    member =
      case params["id"] do
        nil -> nil
        id -> Ash.get!(Valkyrie.Members.Member, id, actor: socket.assigns.current_user)
      end

    action = if is_nil(member), do: "New", else: "Edit"
    page_title = action <> " " <> "Member"

    {:ok,
     socket
     |> assign(:return_to, return_to(params["return_to"]))
     |> assign(member: member)
     |> assign(:key_targets, KeyTargets.all())
     |> assign(:page_title, page_title)
     |> assign_form()}
  end

  defp return_to("show"), do: "show"
  defp return_to(_), do: "index"

  @impl true
  def handle_event("validate", %{"member" => member_params}, socket) do
    member_params = sanitize_key_targets(member_params)
    {:noreply, assign(socket, form: AshPhoenix.Form.validate(socket.assigns.form, member_params))}
  end

  def handle_event("save", %{"member" => member_params}, socket) do
    member_params = sanitize_key_targets(member_params)

    # Set is_manual_entry to true when creating a new member
    member_params =
      if socket.assigns.form.source.type == :create do
        Map.put(member_params, "is_manual_entry", true)
      else
        member_params
      end

    case AshPhoenix.Form.submit(socket.assigns.form, params: member_params) do
      {:ok, member} ->
        notify_parent({:saved, member})

        socket =
          socket
          |> put_flash(:info, "Member #{socket.assigns.form.source.type}d successfully")
          |> push_navigate(to: return_path(socket.assigns.return_to, member))

        Logger.info("Member #{inspect(member)} saved successfully")
        {:noreply, socket}

      {:error, form} ->
        Logger.info("Member #{inspect(form)} saved failed")
        {:noreply, assign(socket, form: form)}
    end
  end

  # The hidden helper input injects an empty entry into key_targets; drop it.
  defp sanitize_key_targets(%{"key_targets" => targets} = params) when is_list(targets) do
    %{params | "key_targets" => Enum.reject(targets, &(&1 == ""))}
  end

  defp sanitize_key_targets(params), do: params

  defp notify_parent(msg), do: send(self(), {__MODULE__, msg})

  defp assign_form(%{assigns: %{member: member}} = socket) do
    form =
      if member do
        AshPhoenix.Form.for_update(member, :update_manual_entry,
          as: "member",
          actor: socket.assigns.current_user
        )
      else
        AshPhoenix.Form.for_create(Valkyrie.Members.Member, :create_manual_entry,
          as: "member",
          actor: socket.assigns.current_user
        )
      end

    assign(socket, form: to_form(form))
  end

  defp return_path("index", _member), do: ~p"/members"
end
