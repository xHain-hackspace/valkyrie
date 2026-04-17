defmodule ValkyrieWeb.AuthorizedKeysControllerTest do
  use ValkyrieWeb.ConnCase

  alias Valkyrie.Members.Member

  @valid_ssh_key "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOn6J0bzZLnNNvMVDzyP63RNQjdT3BgBRZLm2wO+9sZl"
  @invalid_ssh_key "not-a-valid-key"

  defp create_member(attrs) do
    defaults = %{
      username: "testuser",
      xhain_account_id: 1,
      tree_name: "testtree",
      ssh_public_key: @valid_ssh_key,
      is_active: true,
      has_key: true
    }

    Ash.create!(Member, Map.merge(defaults, attrs), action: :create)
  end

  describe "GET /authorized_keys" do
    test "includes active keyholders with a valid SSH key", %{conn: conn} do
      create_member(%{tree_name: "birke"})

      conn = get(conn, ~p"/authorized_keys")

      assert response(conn, 200) =~ "birke"
    end

    test "excludes inactive members", %{conn: conn} do
      create_member(%{tree_name: "eiche", is_active: false})

      conn = get(conn, ~p"/authorized_keys")

      refute response(conn, 200) =~ "eiche"
    end

    test "excludes members without key access", %{conn: conn} do
      create_member(%{tree_name: "linde", has_key: false})

      conn = get(conn, ~p"/authorized_keys")

      refute response(conn, 200) =~ "linde"
    end

    test "excludes members without an SSH key", %{conn: conn} do
      create_member(%{tree_name: "ahorn", ssh_public_key: ""})

      conn = get(conn, ~p"/authorized_keys")

      refute response(conn, 200) =~ "ahorn"
    end

    test "excludes members with an invalid SSH key", %{conn: conn} do
      create_member(%{tree_name: "ulme", ssh_public_key: @invalid_ssh_key})

      conn = get(conn, ~p"/authorized_keys")

      refute response(conn, 200) =~ "ulme"
    end

    test "excludes archived members", %{conn: conn} do
      member = create_member(%{tree_name: "kiefer"})
      Ash.destroy!(member)

      conn = get(conn, ~p"/authorized_keys")

      refute response(conn, 200) =~ "kiefer"
    end

    test "sorts output alphabetically by tree_name", %{conn: conn} do
      create_member(%{username: "zorro", tree_name: "zeder"})
      create_member(%{username: "alice", xhain_account_id: 2, tree_name: "ahorn"})

      body = conn |> get(~p"/authorized_keys") |> response(200)

      ahorn_pos = :binary.match(body, "ahorn") |> elem(0)
      zeder_pos = :binary.match(body, "zeder") |> elem(0)

      assert ahorn_pos < zeder_pos
    end

    test "formats each line as '<protocol> <key> <tree_name>'", %{conn: conn} do
      create_member(%{tree_name: "eiche"})

      body = conn |> get(~p"/authorized_keys") |> response(200)

      assert body =~ ~r/^ssh-ed25519 [A-Za-z0-9+\/]+ eiche$/m
    end
  end

  describe "GET /authorized_keys.sig" do
    test "returns 200 with a non-empty signature body", %{conn: conn} do
      create_member(%{tree_name: "birke"})

      conn = get(conn, ~p"/authorized_keys.sig")

      body = response(conn, 200)
      assert byte_size(body) > 0
    end

    test "returns application/pgp-signature content type", %{conn: conn} do
      conn = get(conn, ~p"/authorized_keys.sig")

      response(conn, 200)
      assert get_resp_header(conn, "content-type") == ["application/pgp-signature"]
    end
  end
end
