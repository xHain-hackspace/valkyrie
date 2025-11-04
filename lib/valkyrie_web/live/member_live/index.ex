defmodule ValkyrieWeb.MemberLive.Index do
  use ValkyrieWeb, :live_view
  require Logger

  alias Valkyrie.Members
  alias Valkyrie.Members.Member
  alias Valkyrie.Members.LastAccess
  alias DateTime

  @last_access_authorized_keys_topic "last_access:authorized_keys"

  def init(_params, _session, socket) do
    Logger.debug("Initializing member live index")
    Valkyrie.Members.access(%{resource_name: "authorized_keys"})
    {:noreply, socket}
  end

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Logger.debug("Subscribing to #{@last_access_authorized_keys_topic}")
      ValkyrieWeb.Endpoint.subscribe(@last_access_authorized_keys_topic)
    end
    {:ok,
     socket
     |> assign(:page_title, "Listing Members")
     |> assign(:updating, false)
     |> assign(:search_query, "")
     |> assign(:pagination, %{page: 1, page_size: 20, total: 0})
     |> assign(:statuses, %{})
     |> update_member_list()}
  end

  @impl true
  def handle_info(%{topic: @last_access_authorized_keys_topic}, socket) do
    {:noreply, update_member_list(socket)}
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    member = Ash.get!(Member, id, actor: socket.assigns.current_user)
    Ash.destroy!(member, actor: socket.assigns.current_user)

    {:noreply, stream_delete(socket, :members, member)}
  end

  @impl true
  def handle_event("pagination", %{"action" => "select", "page" => page}, socket) do
    page =
      case page do
        page when is_integer(page) -> page
        page when is_binary(page) -> String.to_integer(page)
      end

    {:noreply,
     socket
     |> assign(:pagination, %{socket.assigns.pagination | page: page})
     |> update_member_list()}
  end

  @impl true
  def handle_event("pagination", %{"action" => "first"}, socket) do
    {:noreply,
     socket
     |> assign(:pagination, %{socket.assigns.pagination | page: 1})
     |> update_member_list()}
  end

  @impl true
  def handle_event("pagination", %{"action" => "last"}, socket) do
    {:noreply,
     socket
     |> assign(:pagination, %{socket.assigns.pagination | page: socket.assigns.pagination.total})
     |> update_member_list()}
  end

  @impl true
  def handle_event("pagination", %{"action" => "next"}, socket) do
    {:noreply,
     socket
     |> assign(:pagination, %{
       socket.assigns.pagination
       | page: socket.assigns.pagination.page + 1
     })
     |> update_member_list()}
  end

  @impl true
  def handle_event("pagination", %{"action" => "previous"}, socket) do
    {:noreply,
     socket
     |> assign(:pagination, %{
       socket.assigns.pagination
       | page: socket.assigns.pagination.page - 1
     })
     |> update_member_list()}
  end

  @impl true
  def handle_event("search", %{"search_query" => query}, socket) do
    Logger.info("Searching for #{query}")

    {:noreply,
     socket
     |> assign(:search_query, query)
     |> assign(:pagination, %{socket.assigns.pagination | page: 1})
     |> update_member_list()}
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
    socket = assign(socket, :updating, true)

    case Valkyrie.Members.update_members_from_xhain_account_system() do
      {:ok, _members} ->
        {:noreply,
         update_member_list(socket)
         |> assign(:updating, false)
         |> put_flash(:info, "Members synced successfully")}

      {:error, reason} ->
        {:noreply,
         socket
         |> assign(:updating, false)
         |> put_flash(:error, "Failed to sync members: #{reason}")}
    end
  end

  defp update_member_list(socket) do
    page_size = socket.assigns.pagination.page_size
    current_page = socket.assigns.pagination.page
    offset = (current_page - 1) * page_size
    search_query = socket.assigns.search_query |> String.trim()

    search_filter =
      if search_query != "" do
        [username: [contains: "#{search_query}"]]
      else
        []
      end

    case Members.list_members(
           page: [limit: page_size, offset: offset, count: true],
           actor: socket.assigns.current_user,
           query: [
             sort: :username,
             filter: [is_active: true],
             filter_input: search_filter
           ]
         ) do
      {:ok, page} ->
        number_of_pages = div(page.count + page_size - 1, page_size)
        # statuses = Enum.map(page.results, fn member ->
        #   {member.id, get_status(member)}
        # end) |> Enum.into(%{}) |> IO.inspect()
        page = %{page | results: page.results |> Enum.map(&add_status_to_member/1)}

        socket
        # |> assign(:statuses, statuses)
        |> assign(:pagination, %{
          socket.assigns.pagination
          | total: number_of_pages
        })
        |> AshPhoenix.LiveView.assign_page_and_stream_result(page, results_key: :members)

      {:error, reason} ->
        socket
        |> put_flash(:error, "Failed to list members: #{reason}")
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
        status
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
      member.ssh_public_key == "" or member.ssh_public_key == nil ->
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

  defp remove_status_from_member(member) do
    Map.delete(member, :_status)
  end

end
