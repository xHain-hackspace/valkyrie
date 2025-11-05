defmodule ValkyrieWeb.AuditLive.Index do
  use ValkyrieWeb, :live_view
  use ValkyrieWeb.PaginationHelpers, update_function: :update_audit_list

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:search_query, "")
     |> update_audit_list()}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      Audit Log
      <.paginated_content
        search_query={@search_query}
        search_placeholder="Search Entity..."
        page={@page}
      >
        <.table rows={@streams.audit} thead_class="text-lg font-extrabold" rounded="large">
          <:col :let={{_id, version}} label="Timestamp">
            <%= if version.version_inserted_at do %>
              {Calendar.strftime(version.version_inserted_at, "%Y-%m-%d %H:%M:%S")}
            <% else %>
              <span class="font-light italic text-gray-400">unknown</span>
            <% end %>
          </:col>
          <:col :let={{_id, version}} label="Actor">
            <%= if version.user do %>
              {version.user.username}
            <% else %>
              <span class="font-light italic text-gray-400">unknown</span>
            <% end %>
          </:col>
          <:col :let={{_id, version}} label="Changes">
            <%= for {key, value} <- version.changes do %>
              <%= if not Map.has_key?(value, "unchanged") do %>
                <div class="flex flex-col">
                  <span class="font-light text-gray-500">
                    changed {key} from {Map.get(value, "from", "-")} to {Map.get(value, "to", "-")}
                  </span>
                </div>
              <% end %>
            <% end %>
          </:col>
          <:col :let={{_id, version}} label="Action">
            {version.version_action_name}
          </:col>
          <:col :let={{_id, version}} label="Entity">{version.version_source.username}</:col>
        </.table>
      </.paginated_content>
    </Layouts.app>
    """
  end

  def update_audit_list(socket) do
    offset =
      socket.assigns
      |> Map.get(:page, %{})
      |> Map.get(:offset, 0)

    search_filter =
      if socket.assigns.search_query |> String.trim() != "" do
        [version_source: [username: [contains: "#{socket.assigns.search_query}"]]]
      else
        []
      end

    case Valkyrie.Members.list_versions(
           page: [limit: 20, offset: offset, count: true],
           query: [
             sort: [version_inserted_at: :desc],
             filter: [search_filter]
           ]
         ) do
      {:ok, page} ->
        socket
        |> AshPhoenix.LiveView.assign_page_and_stream_result(page, results_key: :audit)

      {:error, error} ->
        socket
        |> put_flash(:error, "Failed to load audit data: #{inspect(error)}")
    end
  end
end
