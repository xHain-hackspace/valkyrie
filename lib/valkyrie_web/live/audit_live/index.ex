defmodule ValkyrieWeb.AuditLive.Index do
  use ValkyrieWeb, :live_view
  use ValkyrieWeb.PaginationHelpers, update_function: :update_audit_list
  require Logger

  require Ash.Query

  alias Valkyrie.Members
  alias Valkyrie.Members.KeyTargets
  alias Valkyrie.Members.Member
  alias Valkyrie.Repo

  @limit 20
  @member_versions_table "members_versions"
  @access_versions_table "member_key_targets_versions"
  # Search scans a bounded recent window per source. Fully unbounded audit search
  # would need a denormalized audit table: the affected member-id and door-id live
  # inside each version's JSON `changes`, not as queryable columns, so they can't be
  # filtered in SQL, and matching many ids reintroduces SQLite's OR-depth limit.
  @search_window 2000

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:search_query, "")
     |> assign(:search_window, @search_window)
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
        <p :if={@search_truncated?} class="text-sm text-gray-500 italic mb-2">
          Showing matches within the most recent {@search_window} events.
        </p>
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
              {entry.actor}
            <% else %>
              <span class="font-light italic text-gray-400">unknown</span>
            <% end %>
          </:col>
          <:col :let={{_id, entry}} label="Action">
            {entry.action}
          </:col>
          <:col :let={{_id, entry}} label="Entity">{entry.entity}</:col>
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

    query = String.trim(socket.assigns.search_query)
    searching? = query != ""
    user_names = user_name_map()

    {results, total, truncated?} =
      if searching? do
        # Entity/door names live inside each version's JSON `changes`, so they can't
        # be filtered in SQL — scan a bounded recent window, resolve, filter in memory.
        window = fetch_raw(@search_window, 0, user_names)
        filtered = window |> resolve_names() |> Enum.filter(&matches?(&1, query))

        {filtered |> Enum.drop(offset) |> Enum.take(@limit), length(filtered),
         length(window) >= @search_window}
      else
        # The database merges + orders + paginates both version tables (see fetch_raw),
        # so deep pages and the total count are correct.
        {fetch_raw(@limit, offset, user_names) |> resolve_names(), total_count(), false}
      end

    page = %Ash.Page.Offset{
      results: results,
      limit: @limit,
      offset: offset,
      count: total,
      more?: offset + @limit < total
    }

    socket
    |> assign(:search_truncated?, truncated?)
    |> AshPhoenix.LiveView.assign_page_and_stream_result(page, results_key: :audit)
  end

  # Merge both version tables in the database. They share a schema, so a UNION lets
  # SQLite do the ordering/limit/offset — doing it in-app is capped by the version
  # read's max page size and cannot reach deep pages.
  defp fetch_raw(limit, offset, user_names) do
    sql = """
    SELECT id, version_inserted_at, user_id, version_action_name, version_action_type, version_source_id, changes, 'member' AS kind
    FROM #{@member_versions_table}
    UNION ALL
    SELECT id, version_inserted_at, user_id, version_action_name, version_action_type, version_source_id, changes, 'access' AS kind
    FROM #{@access_versions_table}
    ORDER BY version_inserted_at DESC
    LIMIT ? OFFSET ?
    """

    %{rows: rows} = Repo.query!(sql, [limit, offset])
    Enum.map(rows, &row_to_raw(&1, user_names))
  end

  defp total_count do
    %{rows: [[count]]} =
      Repo.query!(
        "SELECT (SELECT COUNT(*) FROM #{@member_versions_table}) + " <>
          "(SELECT COUNT(*) FROM #{@access_versions_table})"
      )

    count
  end

  defp row_to_raw(
         [id, inserted_at, user_id, action_name, action_type, source_id, changes_json, kind],
         user_names
       ) do
    changes = decode_changes(changes_json)

    base = %{
      id: id,
      inserted_at: parse_datetime(inserted_at),
      actor: Map.get(user_names, user_id)
    }

    case kind do
      "member" ->
        lines =
          for {key, value} <- changes, line = format_change(key, value), line != "", do: line

        Map.merge(base, %{
          action: to_string(action_name),
          kind: :member,
          member_id: source_id,
          target_id: nil,
          lines: lines
        })

      "access" ->
        action =
          case action_type do
            "create" -> "granted key access"
            "destroy" -> "revoked key access"
            other -> to_string(other)
          end

        Map.merge(base, %{
          action: action,
          kind: :access,
          member_id: change_value(changes["member_id"]),
          target_id: change_value(changes["key_target_id"]),
          lines: nil
        })
    end
  end

  defp decode_changes(json) when is_binary(json), do: Jason.decode!(json)
  defp decode_changes(map) when is_map(map), do: map
  defp decode_changes(_), do: %{}

  defp parse_datetime(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _} ->
        datetime

      _ ->
        case NaiveDateTime.from_iso8601(value) do
          {:ok, naive} -> DateTime.from_naive!(naive, "Etc/UTC")
          _ -> nil
        end
    end
  end

  defp parse_datetime(value), do: value

  defp user_name_map do
    Valkyrie.Accounts.User
    |> Ash.read!(authorize?: false)
    |> Map.new(&{&1.id, &1.username})
  end

  # Resolve member usernames (and, for access rows, door names) for only the given
  # entries — the current page when not searching, or the search window otherwise.
  defp resolve_names(entries) do
    member_ids = entries |> Enum.map(& &1.member_id) |> Enum.reject(&is_nil/1) |> Enum.uniq()
    member_names = member_name_map(member_ids)
    target_names = target_name_lookup()

    Enum.map(entries, fn entry ->
      %{
        id: entry.id,
        inserted_at: entry.inserted_at,
        actor: entry.actor,
        action: entry.action,
        entity: Map.get(member_names, entry.member_id, "unknown"),
        lines: entry_lines(entry, target_names)
      }
    end)
  end

  defp entry_lines(%{kind: :member, lines: lines}, _targets), do: lines

  defp entry_lines(%{kind: :access, target_id: target_id}, targets),
    do: [Map.get(targets, target_id, target_id)]

  defp matches?(entry, query) do
    needle = String.downcase(query)

    haystack =
      [entry.entity, entry.actor, entry.action | entry.lines]
      |> Enum.reject(&is_nil/1)
      |> Enum.join(" ")
      |> String.downcase()

    String.contains?(haystack, needle)
  end

  # Papertrail full_diff wraps each value; a grant stores it under "to", a revoke
  # under "unchanged", and scalar edits under "from"/"to".
  defp change_value(%{"to" => value}), do: value
  defp change_value(%{"unchanged" => value}), do: value
  defp change_value(%{"from" => value}), do: value
  defp change_value(_), do: nil

  # Map of member id -> username for just the given ids (archived members included,
  # so deleted entities still resolve). Scoped to the ids on the current page rather
  # than reading the whole members table on every render. For a large id set (the
  # search window) a scoped `id in [...]` would risk SQLite's variable/expression
  # limits, so fall back to a single unfiltered read.
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
            case change_value(version.changes["name"]) do
              nil -> acc
              name -> Map.put(acc, version.version_source_id, name <> " (deleted)")
            end
          end)

        {:error, _} ->
          %{}
      end

    Map.merge(historical, Map.new(KeyTargets.all(), &{&1.id, &1.name}))
  end
end
