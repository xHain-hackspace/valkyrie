defmodule ValkyrieWeb.AuthorizedKeysController do
  use ValkyrieWeb, :controller
  alias Valkyrie.Members.Member
  require Logger

  @doc """
  Serves the authorized_keys file with SSH public keys from all members.
  """
  def authorized_keys(conn, _params) do
    # get the X-Door header
    x_door =
      conn.req_headers
      |> Enum.find(fn {key, _} -> String.downcase(key) == "X-door-hostname" end)
      |> elem(1)

    Logger.info("Requesting authorized keys for xDoor: #{x_door}")

    Valkyrie.Members.access(%{resource_name: "authorized_keys"})

    conn
    |> put_resp_header("content-type", "application/octet-stream")
    |> text(build_authorized_keys_content())
  end

  @doc """
  Builds the signature for the authorized_keys content.
  """
  def authorized_keys_signature(conn, _params) do
    signature =
      build_authorized_keys_content()
      |> sign()

    conn
    |> put_resp_header("content-type", "application/pgp-signature")
    |> text(signature)
  end

  defp build_authorized_keys_content() do
    Ash.read!(Member)
    |> Enum.sort_by(fn member -> member.tree_name end)
    |> Enum.filter(fn %Member{} = m -> m.has_key end)
    |> Enum.filter(fn %Member{} = m -> Member.ssh_public_key_valid?(m.ssh_public_key) end)
    |> Enum.map(&get_ssh_pub_key_for_list/1)
    |> Enum.join("\n")
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
