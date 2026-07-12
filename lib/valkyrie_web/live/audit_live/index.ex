defmodule ValkyrieWeb.AuditLive.Index do
  use ValkyrieWeb, :live_view
  use ValkyrieWeb.PaginationHelpers, update_function: :update_audit_list
  require Logger

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
    <Layouts.app flash={@flash} current_user={@current_user}>
      Audit Log
      <.paginated_content
        search_query={@search_query}
        search_placeholder="Search Entity..."
        page={@page}
      >
        <.table id="audit" rows={@streams.audit} thead_class="text-lg font-extrabold" rounded="large">
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
          <:col :let={{_id, version}} label="Action">
            {version.version_action_name}
          </:col>
          <:col :let={{_id, version}} label="Entity">{version.version_source.username}</:col>
          <:col :let={{_id, version}} label="Changes">
            <%= for {key, value} <- version.changes, line = format_change(key, value), line != "" do %>
              <div class="flex flex-col">
                <span class="font-light text-gray-500 break-all">{line}</span>
              </div>
            <% end %>
          </:col>
        </.table>
      </.paginated_content>
    </Layouts.app>
    """
  end

  @doc false
  # Renders one papertrail change entry as a human-readable line, or "" when the
  # attribute is unchanged (so the caller can skip it).
  #
  # Scalars arrive as %{"from" => a, "to" => b}. Array attributes (full_diff)
  # arrive as %{"to" => [%{"added" => v}, %{"removed" => v}, %{"unchanged" => v}]},
  # which we render as an explicit "added ...; removed ..." summary.
  def format_change(_key, %{"unchanged" => _}), do: ""

  def format_change(key, %{"to" => elements}) when is_list(elements) do
    added = for %{"added" => v} <- elements, do: to_string(v)
    removed = for %{"removed" => v} <- elements, do: to_string(v)

    parts =
      [] ++
        if(added == [], do: [], else: ["added #{Enum.join(added, ", ")}"]) ++
        if(removed == [], do: [], else: ["removed #{Enum.join(removed, ", ")}"])

    case parts do
      [] -> ""
      _ -> "changed #{key}: #{Enum.join(parts, "; ")}"
    end
  end

  def format_change(key, %{"from" => from, "to" => to}) do
    "changed #{key} from #{format_audit_value(from)} to #{format_audit_value(to)}"
  end

  # A scalar set on create arrives as %{"to" => value} with no "from".
  def format_change(key, %{"to" => to}) do
    "changed #{key} from #{format_audit_value(nil)} to #{format_audit_value(to)}"
  end

  def format_change(_key, _value), do: ""

  @doc false
  # Renders a scalar papertrail value as a display string.
  def format_audit_value(value) when value in [nil, ""], do: "<empty>"
  def format_audit_value(value) when is_binary(value), do: value
  def format_audit_value(value), do: inspect(value)

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
        # load the version_source for each version manually using a custom action which
        # also loads the member if it was soft deleted
        page = %{
          page
          | results: page.results |> Enum.map(&load_version_source/1)
        }

        socket
        |> AshPhoenix.LiveView.assign_page_and_stream_result(page, results_key: :audit)

      {:error, error} ->
        socket
        |> put_flash(:error, "Failed to load audit data: #{inspect(error)}")
    end
  end

  defp load_version_source(%{version_source_id: version_source_id} = version) do
    case Ash.get(Valkyrie.Members.Member, version_source_id, action: :read_for_audit_log) do
      {:ok, version_source} ->
        Map.put(version, :version_source, version_source)

      {:error, error} ->
        Logger.error("Failed to load version source: #{inspect(error)}")
        version
    end
  end
end
