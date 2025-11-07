defmodule Valkyrie.Authentik do
  require Logger

  defmodule XHainAccount do
    defstruct [
      :username,
      :xhain_account_id,
      :ssh_public_key,
      :tree_name,
      :groups
    ]
  end

  @page_size 100

  defp bearer_token do
    Application.fetch_env!(:valkyrie, :authentik_token)
  end

  defp base_url do
    Application.fetch_env!(:valkyrie, :authentik_url)
  end

  defp do_get_all_users(page, acc, progress_callback) do
    Logger.debug("Fetching users from page #{page}")

    url = "#{base_url()}/api/v3/core/users/"

    case Req.get(url,
           auth: {:bearer, bearer_token()},
           params: [page: page, page_size: @page_size, is_active: true],
           receive_timeout: 20_000
         ) do
      {:ok, %Req.Response{status: 200, body: %{"results" => results, "pagination" => pagination}}} ->
        new_acc = Enum.concat(acc, results)

        # Calculate total pages if available in pagination
        total_pages =
          case pagination do
            %{"count" => count} when is_integer(count) ->
              # Calculate total pages from count and page_size
              ceil(count / @page_size)

            _ ->
              nil
          end

        # Call progress callback if provided
        if not is_nil(progress_callback) do
          progress_callback.(%{
            page: page,
            total_pages: total_pages,
            users_fetched: length(new_acc),
            status: :in_progress
          })
        end

        case pagination["next"] do
          next_page when next_page > 0 and is_integer(next_page) ->
            # Fetch next page recursively
            do_get_all_users(next_page, new_acc, progress_callback)

          _ ->
            # No more pages
            {:ok, new_acc}
        end

      {:ok, %Req.Response{status: status}} ->
        {:error, "API returned status #{status}"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def get_all_users(progress_callback \\ nil) do
    case do_get_all_users(1, [], progress_callback) do
      {:ok, users} ->
        {:ok,
         users
         |> Enum.filter(&(not is_service_user(&1)))
         |> Enum.map(fn user ->
           %XHainAccount{
             username: Map.get(user, "username"),
             xhain_account_id: Map.get(user, "pk"),
             ssh_public_key: Map.get(user, "attributes", %{}) |> Map.get("ssh-key", ""),
             tree_name: Map.get(user, "attributes", %{}) |> Map.get("tree"),
             groups: Map.get(user, "groups", [])
           }
         end)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp is_service_user(user) do
    Map.get(user, "type")
    |> String.downcase()
    |> String.trim()
    |> String.contains?("service")
  end
end
