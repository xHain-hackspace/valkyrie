defmodule ValkyrieWeb.MemberLive.Index do
  use ValkyrieWeb, :live_view
  use ValkyrieWeb.PaginationHelpers, update_function: :update_member_list
  require Logger
  require Ash.Query

  alias Valkyrie.Members
  alias Valkyrie.Members.Member
  alias Valkyrie.Members.LastAccess
  alias Valkyrie.Members.SyncState
  alias DateTime

  @last_access_authorized_keys_topic "last_access:authorized_keys"

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      ValkyrieWeb.Endpoint.subscribe(@last_access_authorized_keys_topic)
      ValkyrieWeb.Endpoint.subscribe("sync_members:progress")
    end

    {:ok,
     socket
     |> assign(:page_title, "Listing Members")
     |> assign(:updating, false)
     |> assign(:sync_progress, nil)
     |> assign(:search_query, "")
     |> assign(:filters, %{
       "only_manual_entries" => false,
       "only_active_members" => true,
       "only_keyholders" => false
     })
     |> update_member_list()}
  end

  @impl true
  def handle_info(%{topic: @last_access_authorized_keys_topic}, socket) do
    {:noreply, update_member_list(socket)}
  end

  @impl true
  def handle_info({ref, _result}, socket) when is_reference(ref) do
    # Ignore Task completion messages - we handle progress via PubSub
    {:noreply, socket}
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, _pid, _reason}, socket) do
    # Ignore Task termination messages - we handle completion via PubSub
    {:noreply, socket}
  end

  @impl true
  def handle_info({:sync_progress, progress}, socket) do
    socket =
      socket
      |> assign(:sync_progress, progress)

    socket =
      case progress.status do
        :completed ->
          socket
          |> put_flash(:info, "Members synced successfully (#{progress.users_fetched} users)")
          |> assign(:sync_progress, nil)
          |> update_member_list()

        :error ->
          error_msg = Map.get(progress, :error, "Unknown error")

          socket
          |> put_flash(:error, "Failed to sync members: #{error_msg}")
          |> assign(:sync_progress, nil)

        _ ->
          socket
      end

    {:noreply, socket}
  end

  defp filters_from_form(form) do
    form
    |> Map.reject(fn {key, _value} -> String.starts_with?(key, "_") end)
    |> Enum.map(fn {key, value} ->
      {key, Phoenix.HTML.Form.normalize_value("checkbox", value)}
    end)
    |> Map.new()
  end

  @impl true
  def handle_event("filter_changed", form, socket) do
    {:noreply, socket |> assign(:filters, filters_from_form(form)) |> update_member_list()}
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    member = Ash.get!(Member, id, actor: socket.assigns.current_user)
    Ash.destroy!(member, actor: socket.assigns.current_user)

    {:noreply, stream_delete(socket, :members, member)}
  end

  @impl true
  def handle_event("toggle_has_key", %{"member-id" => member_id} = params, socket) do
    desired = Map.get(params, "value") == "true"
    member = Ash.get!(Member, member_id, actor: socket.assigns.current_user)

    case Members.change_keyholder_status(member, %{has_key: desired},
           actor: socket.assigns.current_user
         ) do
      {:ok, updated} ->
        Logger.info("Updated member #{member_id}: #{inspect(updated)}")
        {:noreply, stream_insert(socket, :members, add_status_to_member(updated))}

      {:error, _reason} ->
        Logger.error("Failed to update member #{member_id}")
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("sync_members", _params, socket) do
    # Check if sync is already running
    if SyncState.is_syncing?() do
      {:noreply,
       socket
       |> put_flash(:error, "Sync is already in progress. Please wait for it to complete.")}
    else
      # Start async sync
      case Members.update_members_from_xhain_account_system_async() do
        {:ok, _task} ->
          {:noreply,
           socket
           |> assign(:sync_progress, %{
             page: nil,
             total_pages: nil,
             users_fetched: 0,
             status: :in_progress
           })}

        {:error, reason} ->
          {:noreply,
           socket
           |> put_flash(:error, "Failed to start sync: #{reason}")}
      end
    end
  end

  def update_member_list(socket) do
    offset =
      socket.assigns
      |> Map.get(:page, %{})
      |> Map.get(:offset, 0)

    query =
      Member
      |> Ash.Query.sort(:username)
      |> maybe_add_search_filter(socket.assigns.search_query)
      |> maybe_filter_only_active_members(socket)
      |> maybe_filter_only_manual_entries(socket)
      |> maybe_filter_only_keyholders(socket)

    case Members.list_members(
           page: [limit: 20, offset: offset, count: true],
           actor: socket.assigns.current_user,
           query: query
         ) do
      {:ok, page} ->
        page = %{page | results: page.results |> Enum.map(&add_status_to_member/1)}

        socket
        |> AshPhoenix.LiveView.assign_page_and_stream_result(page, results_key: :members)

      {:error, reason} ->
        socket
        |> put_flash(:error, "Failed to list members: #{reason}")
    end
  end

  defp maybe_filter_only_manual_entries(query, socket) do
    if socket.assigns.filters["only_manual_entries"] == true do
      query |> Ash.Query.filter(is_manual_entry: true)
    else
      query
    end
  end

  defp maybe_filter_only_active_members(query, socket) do
    if socket.assigns.filters["only_active_members"] == true do
      query |> Ash.Query.filter(is_active: true)
    else
      query
    end
  end

  defp maybe_filter_only_keyholders(query, socket) do
    if socket.assigns.filters["only_keyholders"] == true do
      query |> Ash.Query.filter(has_key: true)
    else
      query
    end
  end

  defp maybe_add_search_filter(query, search_query) do
    if search_query |> String.trim() != "" do
      query |> Ash.Query.filter_input(username: [contains: search_query])
    else
      query
    end
  end

  defp get_status(member) do
    []
    |> maybe_add_manual_entry_status(member)
    |> maybe_add_invalid_ssh_key_status(member)
    |> add_authorized_keys_status(member)
  end

  defp add_authorized_keys_status(status, member) do
    case Ash.get(LastAccess, %{resource_name: "authorized_keys"}) do
      {:ok, %LastAccess{last_access: last_access}} ->
        if DateTime.diff(last_access, member.updated_at, :second) > 0 do
          [{:synced, "State synced to door."} | status]
        else
          [{:warning, "State not yet synced to door."} | status]
        end

      _ ->
        [{:warning, "State not yet synced to door."} | status]
    end
  end

  defp maybe_add_manual_entry_status(status, member) do
    if member.is_manual_entry == true do
      [{:info, "Manual entry"} | status]
    else
      status
    end
  end

  defp maybe_add_invalid_ssh_key_status(status, member) do
    cond do
      is_nil(member.ssh_public_key) or member.ssh_public_key == "" ->
        status

      not Member.ssh_public_key_valid?(member.ssh_public_key) ->
        [{:warning, "Invalid SSH public key"} | status]

      true ->
        status
    end
  end

  defp add_status_to_member(member) do
    Map.put(member, :_status, get_status(member))
  end
end
