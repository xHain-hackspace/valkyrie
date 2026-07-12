defmodule ValkyrieWeb.AuthorizedKeysController do
  use ValkyrieWeb, :controller
  require Ash.Query
  alias Valkyrie.Members.KeyTargets
  alias Valkyrie.Members.Member

  @doc """
  Serves the combined authorized_keys file: the deduplicated union of every
  target's keys (any active member with a valid key that has access to at least
  one target).
  """
  def authorized_keys(conn, _params) do
    track_access(conn, "authorized_keys")

    conn
    |> put_resp_header("content-type", "application/octet-stream")
    |> text(build_union())
  end

  @doc """
  Builds the signature for the combined authorized_keys content.
  """
  def authorized_keys_signature(conn, _params) do
    conn
    |> put_resp_header("content-type", "application/pgp-signature")
    |> text(sign(build_union()))
  end

  @doc """
  Serves the authorized_keys file (or its signature, for a `.sig` suffix) for a
  single key access target identified by its slug.
  """
  def authorized_keys_for_target(conn, %{"target" => target}) do
    {slug, signature?} = parse_target(target)

    cond do
      not KeyTargets.valid_slug?(slug) ->
        send_resp(conn, 404, "")

      signature? ->
        conn
        |> put_resp_header("content-type", "application/pgp-signature")
        |> text(sign(build_for_target(slug)))

      true ->
        track_access(conn, "authorized_keys:" <> slug)

        conn
        |> put_resp_header("content-type", "application/octet-stream")
        |> text(build_for_target(slug))
    end
  end

  defp parse_target(target) do
    case String.split(target, ".sig", parts: 2) do
      [slug, ""] -> {slug, true}
      _ -> {target, false}
    end
  end

  # Track access only if the xdoor header is set.
  defp track_access(conn, resource_name) do
    case get_req_header(conn, "x-door") do
      [_] -> Valkyrie.Members.access(%{resource_name: resource_name})
      [] -> nil
    end
  end

  defp build_for_target(slug) do
    # Filter to members granted this target in SQL (via the join) rather than
    # loading every member's key_targets — a large member set would otherwise
    # blow SQLite's expression-depth limit.
    Member
    |> Ash.Query.filter(exists(key_target_accesses, key_target.slug == ^slug))
    |> eligible_members()
    |> Enum.map(&get_ssh_pub_key_for_list/1)
    |> Enum.join("\n")
  end

  defp build_union() do
    Member
    |> Ash.Query.filter(exists(key_target_accesses, true))
    |> eligible_members()
    |> Enum.map(&get_ssh_pub_key_for_list/1)
    |> Enum.uniq()
    |> Enum.join("\n")
  end

  defp eligible_members(query) do
    query
    |> Ash.Query.filter(is_active == true)
    |> Ash.read!()
    |> Enum.sort_by(fn member -> member.tree_name end)
    |> Enum.filter(fn %Member{} = m -> Member.ssh_public_key_valid?(m.ssh_public_key) end)
  end

  defp get_ssh_pub_key_for_list(%{ssh_public_key: nil}), do: nil
  defp get_ssh_pub_key_for_list(%{ssh_public_key: ""}), do: nil

  defp get_ssh_pub_key_for_list(member) do
    [proto, core | _] = String.split(member.ssh_public_key, " ")
    "#{proto} #{core} #{member.tree_name}"
  end

  defp sign(binary) do
    priv_key =
      Application.fetch_env!(:valkyrie, :xdoor_signing_key)
      |> ExPublicKey.loads!()

    {:ok, signature} = ExPublicKey.sign(binary, priv_key)
    Base.encode64(signature)
  end
end
