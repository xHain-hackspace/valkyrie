defmodule ValkyrieWeb.AuthorizedKeysControllerTest do
  use ValkyrieWeb.ConnCase

  alias Valkyrie.Members.KeyTarget

  @invalid_ssh_key "not-a-valid-key"

  setup do
    ensure_key_targets()
    :ok
  end

  defp create_member(attrs) do
    member_fixture(Map.merge(%{tree_name: "testtree"}, Map.new(attrs)))
  end

  defp key_target_by_slug(slug) do
    KeyTarget |> Ash.read!() |> Enum.find(&(&1.slug == slug))
  end

  describe "GET /authorized_keys (union)" do
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

    test "excludes members without access to any target", %{conn: conn} do
      create_member(%{tree_name: "linde", key_targets: []})

      conn = get(conn, ~p"/authorized_keys")

      refute response(conn, 200) =~ "linde"
    end

    test "includes members with access to only one target", %{conn: conn} do
      create_member(%{tree_name: "birke", key_targets: ["g18"]})

      conn = get(conn, ~p"/authorized_keys")

      assert response(conn, 200) =~ "birke"
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

    test "deduplicates identical key lines across targets", %{conn: conn} do
      create_member(%{tree_name: "birke", key_targets: ["g16", "g18", "g20"]})

      body = conn |> get(~p"/authorized_keys") |> response(200)

      lines = body |> String.split("\n", trim: true)
      assert lines == Enum.uniq(lines)
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

  describe "GET /authorized_keys/:target" do
    test "includes only members granted that target", %{conn: conn} do
      create_member(%{username: "a", tree_name: "birke", key_targets: ["g16"]})

      create_member(%{
        username: "b",
        xhain_account_id: 2,
        tree_name: "eiche",
        key_targets: ["g18"]
      })

      body = conn |> get(~p"/authorized_keys/g16") |> response(200)

      assert body =~ "birke"
      refute body =~ "eiche"
    end

    test "excludes inactive members even if granted the target", %{conn: conn} do
      create_member(%{tree_name: "linde", is_active: false, key_targets: ["g16"]})

      body = conn |> get(~p"/authorized_keys/g16") |> response(200)

      refute body =~ "linde"
    end

    test "returns 404 for an unknown target", %{conn: conn} do
      conn = get(conn, ~p"/authorized_keys/bogus")

      assert response(conn, 404)
    end

    test "returns 200 with an empty body for a target nobody is granted", %{conn: conn} do
      create_member(%{tree_name: "birke", key_targets: ["g16"]})

      body = conn |> get(~p"/authorized_keys/g20") |> response(200)

      assert body == ""
    end
  end

  describe "target deletion revokes access" do
    test "removes the target path and drops members whose only grant it was",
         %{conn: conn} do
      key_target_fixture(%{slug: "garden", name: "Garden"})

      # A is granted only the garden target; B also has g16.
      create_member(%{username: "a", tree_name: "birke", key_targets: ["garden"]})

      create_member(%{
        username: "b",
        xhain_account_id: 2,
        tree_name: "eiche",
        key_targets: ["g16", "garden"]
      })

      "garden" |> key_target_by_slug() |> Ash.destroy!()

      # The target path no longer exists.
      assert response(get(conn, ~p"/authorized_keys/garden"), 404)

      # Union: A (sole grant removed) is gone, B (still has g16) remains.
      union = conn |> get(~p"/authorized_keys") |> response(200)
      refute union =~ "birke"
      assert union =~ "eiche"

      # B still served under the target they keep.
      assert conn |> get(~p"/authorized_keys/g16") |> response(200) =~ "eiche"
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

  describe "GET /authorized_keys/:target.sig" do
    test "returns a signature for the target", %{conn: conn} do
      create_member(%{tree_name: "birke", key_targets: ["g16"]})

      conn = get(conn, ~p"/authorized_keys/g16.sig")

      body = response(conn, 200)
      assert byte_size(body) > 0
      assert get_resp_header(conn, "content-type") == ["application/pgp-signature"]
    end

    test "returns 404 for an unknown target signature", %{conn: conn} do
      conn = get(conn, ~p"/authorized_keys/bogus.sig")

      assert response(conn, 404)
    end
  end
end
