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

  defp bearer_token do
    Application.fetch_env!(:valkyrie, :authentik_token)
  end

  defp base_url do
    Application.fetch_env!(:valkyrie, :authentik_url)
  end

  defp client do
    middleware = [
      {Tesla.Middleware.BaseUrl, base_url()},
      {Tesla.Middleware.BearerAuth, token: bearer_token()},
      {Tesla.Middleware.JSON, engine: JSON}
    ]

    adapter = {Tesla.Adapter.Mint, timeout: 20_000}

    Tesla.client(middleware, adapter)
  end

  defp do_get_all_users(page \\ 1, acc \\ []) do
    Logger.debug("Fetching users from page #{page}")

    case Tesla.get(client(), "/api/v3/core/users/",
           query: [page: page,  page_size: 500, is_active: true]
         ) do
      {:ok, %Tesla.Env{status: 200, body: %{"results" => results, "pagination" => pagination}}} ->
        Logger.debug("Found #{length(results)} users on page #{page}")

        new_acc = Enum.concat(acc, results)

        case pagination["next"] do
          next_page when next_page > 0 and is_integer(next_page) ->
            # Fetch next page recursively
            do_get_all_users(next_page, new_acc)

          _ ->
            # No more pages
            {:ok, new_acc}
        end

      {:ok, %Tesla.Env{status: status}} when status != 200 ->
        {:error, "API returned status #{status}"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def get_all_users do
    case do_get_all_users() do
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
