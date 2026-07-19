defmodule ValkyrieWeb.AuditLive.Index do
  use ValkyrieWeb, :live_view
  use ValkyrieWeb.PaginationHelpers, update_function: :update_audit_list
  require Logger

  require Ash.Query

  alias Valkyrie.Members
  alias Valkyrie.Members.KeyTargets
  alias Valkyrie.Members.Member
  alias Valkyrie.Versions.ChangeFormatter
  alias Valkyrie.Versions.CombinedVersion

  @page_limit 100

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:search_query, "")
     |> assign(:filters, %{
       "show_sync_actions" => false
     })
     |> update_audit_list()}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user}>
      <.header>
        <:actions>
          <div class="flex flex-row gap-20 items-center">
            <div>
              <.form_wrapper
                for={to_form(@filters)}
                phx-change="filter_changed"
                phx-debounce="600"
              >
                <div class="flex flex-row gap-5">
                  <.toggle_field
                    field={@filters[:show_sync_actions]}
                    checked={toggle_check(:show_sync_actions, to_form(@filters))}
                    label="Show Sync Actions"
                    name="show_sync_actions"
                    class="flex flex-col gap-2 items-center"
                  />
                </div>
              </.form_wrapper>
            </div>
          </div>
        </:actions>
      </.header>
      <.paginated_content
        search_query={@search_query}
        search_placeholder="Search Entity..."
        page={@page}
      >
        <.table id="audit" rows={@streams.audit} thead_class="text-lg font-extrabold" rounded="large">
          <:col :let={{_id, entry}} label="Timestamp">
            <%= if entry.inserted_at do %>
              {Calendar.strftime(entry.inserted_at, "%Y-%m-%d %H:%M:%S")}
            <% else %>
              <span class="font-light italic text-gray-400">unknown</span>
            <% end %>
          </:col>
          <:col :let={{_id, entry}} label="Actor">
            <%= if entry.actor do %>
              {entry.actor.username}
            <% else %>
              <span class="font-light italic text-gray-400">unknown</span>
            <% end %>
          </:col>
          <:col :let={{_id, entry}} label="Action">
            {entry.action}
          </:col>
          <:col :let={{_id, entry}} label="Entity">
            <%= if entry.entity do %>
              {entry.entity}
            <% else %>
              <span class="font-light italic text-gray-400">unknown</span>
            <% end %>
          </:col>
          <:col :let={{_id, entry}} label="Changes">
            <div :for={line <- entry.lines} class="flex flex-col">
              <span class="font-light text-gray-500 break-all">{line}</span>
            </div>
          </:col>
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

    query =
      CombinedVersion
      |> Ash.Query.sort(inserted_at: :desc)
      |> maybe_filter_sync_actions(socket)
      |> maybe_add_search_filter(socket.assigns.search_query)

    case Valkyrie.Versions.list_versions(
           page: [limit: @page_limit, offset: offset, count: true],
           actor: socket.assigns.current_user,
           query: query
         ) do
      {:ok, page} ->
        page = %{page | results: resolve_names(page.results)}

        socket
        |> AshPhoenix.LiveView.assign_page_and_stream_result(page, results_key: :audit)

      {:error, reason} ->
        socket
        |> put_flash(:error, "Failed to list audit events: #{inspect(reason)}")
    end
  end

  # Batch-resolves each version's affected member (the Entity column) and, for access
  # grants/revokes, the door name (the Changes column) for the current page, mapping
  # records into the render-friendly shape. The member/door ids are surfaced by the
  # view as the `member_id` / `key_target_id` columns.
  defp resolve_names(records) do
    member_ids =
      records
      |> Enum.map(& &1.member_id)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()

    member_names = member_name_map(member_ids)
    target_names = target_name_lookup()

    Enum.map(records, fn record ->
      %{
        id: record.id,
        inserted_at: record.inserted_at,
        actor: record.actor,
        action: display_action(record),
        entity: Map.get(member_names, record.member_id),
        lines: lines_for(record, target_names)
      }
    end)
  end

  # Access grants/revokes are recorded as raw create/destroy versions on the join
  # resource; surface them as the domain event instead.
  defp display_action(%{kind: "access", version_action_type: "create"}), do: "granted key access"
  defp display_action(%{kind: "access", version_action_type: "destroy"}), do: "revoked key access"
  defp display_action(%{action: action}), do: action

  defp lines_for(%{kind: "access", version_action_type: type, key_target_id: id}, targets) do
    door = Map.get(targets, id, id)

    case type do
      "create" -> ["Granted access to #{door}"]
      "destroy" -> ["Revoked access to #{door}"]
      _ -> [door]
    end
  end

  defp lines_for(%{changes: changes}, _targets), do: ChangeFormatter.summarize(changes)

  # Map of member id -> username for just the given ids (archived members included,
  # so deleted entities still resolve). Scoped to the ids on the current page rather
  # than reading the whole members table on every render. For a large id set a scoped
  # `id in [...]` would risk SQLite's variable/expression limits, so fall back to a
  # single unfiltered read.
  defp member_name_map([]), do: %{}

  defp member_name_map(ids) when length(ids) > 200 do
    Member
    |> Ash.read!(action: :read_for_audit_log)
    |> Map.new(&{&1.id, &1.username})
  end

  defp member_name_map(ids) do
    Member
    |> Ash.Query.filter(id in ^ids)
    |> Ash.read!(action: :read_for_audit_log)
    |> Map.new(&{&1.id, &1.username})
  end

  # Map of key target id -> name. Doors are hard-deleted, so a deleted door's name
  # is recovered from its paper-trail history (its versions survive the delete),
  # with current doors taking precedence.
  defp target_name_lookup do
    historical =
      case Members.list_key_target_versions(query: [sort: [version_inserted_at: :asc]]) do
        {:ok, versions} ->
          Enum.reduce(versions, %{}, fn version, acc ->
            case ChangeFormatter.change_value(version.changes["name"]) do
              nil -> acc
              name -> Map.put(acc, version.version_source_id, name <> " (deleted)")
            end
          end)

        {:error, _} ->
          %{}
      end

    Map.merge(historical, Map.new(KeyTargets.all(), &{&1.id, &1.name}))
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
    filters = filters_from_form(form)

    {:noreply,
     socket
     |> assign(:filters, filters)
     |> reset_offset()
     |> update_audit_list()}
  end

  # Changing filters can shrink the result set below the current offset, leaving the
  # user on a now-out-of-range page; jump back to the first page.
  defp reset_offset(%{assigns: %{page: %{} = page}} = socket),
    do: assign(socket, :page, %{page | offset: 0})

  defp reset_offset(socket), do: socket

  defp maybe_filter_sync_actions(query, socket) do
    if socket.assigns.filters["show_sync_actions"] == true do
      query
    else
      query |> Ash.Query.filter(action != "sync_update")
    end
  end

  # Matches rows by the affected member (who it was done to) — the `member_id` column
  # is present for both kinds, so the id set (pre-resolved from the members table,
  # archived members included) filters via a single `IN`.
  defp maybe_add_search_filter(query, search_query) do
    case String.trim(search_query) do
      "" ->
        query

      trimmed ->
        member_ids =
          Member
          |> Ash.Query.filter(contains(username, ^trimmed))
          |> Ash.read!(action: :read_for_audit_log)
          |> Enum.map(& &1.id)

        Ash.Query.filter(query, member_id in ^member_ids)
    end
  end
end
