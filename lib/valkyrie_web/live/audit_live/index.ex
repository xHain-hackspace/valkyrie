defmodule ValkyrieWeb.AuditLive.Index do
  use ValkyrieWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:pagination, %{
       page: 1,
       page_size: 100,
       total: 0,
       total_pages: 0
     })
     |> assign(:search_query, "")
     |> update_audit_list()}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <.header>
        <:title>Audit</:title>
      </.header>
      <.paginated_content search_query={@search_query} pagination={@pagination}>
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
          <:col :let={{_id, version}} label="Entity">{version.version_source.username}</:col>
        </.table>
      </.paginated_content>
    </Layouts.app>
    """
  end

  defp update_audit_list(socket) do
    page_size = socket.assigns.pagination.page_size
    current_page = socket.assigns.pagination.page
    offset = (current_page - 1) * page_size

    case Valkyrie.Members.list_versions(
           page: [limit: page_size, offset: offset, count: true],
           query: [
             sort: [version_inserted_at: :desc]
           ]
         ) do
      {:ok, page} ->
        number_of_pages = div(page.count + page_size - 1, page_size)

        page.results |> Enum.at(length(page.results) - 1) |> IO.inspect()

        socket
        |> assign(:pagination, %{
          socket.assigns.pagination
          | total: number_of_pages
        })
        |> AshPhoenix.LiveView.assign_page_and_stream_result(page, results_key: :audit)

      {:error, error} ->
        socket
        |> put_flash(:error, "Failed to load audit data: #{inspect(error)}")
    end
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
     |> update_audit_list()}
  end

  @impl true
  def handle_event("pagination", %{"action" => "first"}, socket) do
    {:noreply,
     socket
     |> assign(:pagination, %{socket.assigns.pagination | page: 1})
     |> update_audit_list()}
  end

  @impl true
  def handle_event("pagination", %{"action" => "last"}, socket) do
    {:noreply,
     socket
     |> assign(:pagination, %{socket.assigns.pagination | page: socket.assigns.pagination.total})
     |> update_audit_list()}
  end

  @impl true
  def handle_event("pagination", %{"action" => "next"}, socket) do
    {:noreply,
     socket
     |> assign(:pagination, %{
       socket.assigns.pagination
       | page: socket.assigns.pagination.page + 1
     })
     |> update_audit_list()}
  end

  @impl true
  def handle_event("pagination", %{"action" => "previous"}, socket) do
    {:noreply,
     socket
     |> assign(:pagination, %{
       socket.assigns.pagination
       | page: socket.assigns.pagination.page - 1
     })
     |> update_audit_list()}
  end
end
