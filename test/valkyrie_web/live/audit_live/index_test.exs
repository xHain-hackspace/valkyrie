defmodule ValkyrieWeb.AuditLive.IndexTest do
  use ValkyrieWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Valkyrie.Members
  alias Valkyrie.Members.KeyTargets
  alias ValkyrieWeb.AuditLive.Index

  defp target_id(slug), do: Enum.find(KeyTargets.all(), &(&1.slug == slug)).id

  describe "format_change/2" do
    test "renders scalar from/to changes" do
      assert Index.format_change("tree_name", %{"from" => "aloe", "to" => "birke"}) ==
               "changed tree_name from aloe to birke"
    end

    test "renders a scalar set (create) with an empty from" do
      assert Index.format_change("username", %{"to" => "alice"}) ==
               "changed username from <empty> to alice"
    end

    test "renders array diffs as an explicit added/removed summary" do
      value = %{
        "to" => [
          %{"index" => %{"unchanged" => 0}, "unchanged" => "g16"},
          %{"added" => "g18", "index" => %{"to" => 1}},
          %{"index" => %{"to" => 1}, "removed" => "g20"}
        ]
      }

      assert Index.format_change("key_targets", value) ==
               "changed key_targets: added g18; removed g20"
    end

    test "renders an array create with only additions" do
      value = %{
        "to" => [
          %{"added" => "g16", "index" => %{"to" => 0}},
          %{"added" => "g20", "index" => %{"to" => 1}}
        ]
      }

      assert Index.format_change("key_targets", value) == "changed key_targets: added g16, g20"
    end

    test "skips unchanged attributes" do
      assert Index.format_change("tree_name", %{"unchanged" => "aloe"}) == ""

      unchanged_array = %{
        "unchanged" => [%{"index" => %{"unchanged" => 0}, "unchanged" => "g16"}]
      }

      assert Index.format_change("key_targets", unchanged_array) == ""
    end
  end

  describe "key access audit trail" do
    setup do
      ensure_key_targets()
      :ok
    end

    test "a grant appears with the member, door and action", %{conn: conn} do
      member = member_fixture(%{username: "alice", key_targets: []})

      Members.change_keyholder_status(member, %{key_target_ids: [target_id("g16")]})

      {:ok, _view, html} = live(conn, ~p"/members/audit")

      assert html =~ "granted key access"
      assert html =~ "alice"
      assert html =~ "xHain G16"
    end

    test "a revoke appears as a revoked key access entry", %{conn: conn} do
      member = member_fixture(%{username: "bob", key_targets: ["g16"]})

      Members.change_keyholder_status(member, %{key_target_ids: []})

      {:ok, _view, html} = live(conn, ~p"/members/audit")

      assert html =~ "revoked key access"
      assert html =~ "bob"
    end

    test "search finds a grant by member username", %{conn: conn} do
      member = member_fixture(%{username: "dave", key_targets: []})
      Members.change_keyholder_status(member, %{key_target_ids: [target_id("g16")]})

      {:ok, view, _html} = live(conn, ~p"/members/audit")

      html = render_hook(view, "search", %{"search_query" => "dave"})

      assert html =~ "granted key access"
      assert html =~ "dave"
    end

    test "deep pagination reaches the oldest entries", %{conn: conn} do
      # 30 grants -> 30 access versions -> 2 pages of 20.
      for i <- 1..30 do
        n = String.pad_leading(to_string(i), 3, "0")

        %{username: "user#{n}", xhain_account_id: 100 + i, key_targets: []}
        |> member_fixture()
        |> Members.change_keyholder_status(%{key_target_ids: [target_id("g16")]})
      end

      {:ok, view, html} = live(conn, ~p"/members/audit")

      # Page 1 = newest; the oldest grant is not here.
      assert html =~ "user030"
      refute html =~ "user001"

      # Page 2 = older entries, reachable via a real SQL offset (previously capped).
      page2 = render_hook(view, "pagination", %{"action" => "next"})
      assert page2 =~ "user001"
    end

    test "a deleted door's name still resolves from paper-trail history", %{conn: conn} do
      member = member_fixture(%{username: "carol", key_targets: []})
      door = key_target_fixture(%{slug: "vault", name: "The Vault"})

      Members.change_keyholder_status(member, %{key_target_ids: [door.id]})
      # Hard delete: the FK cascade removes the join rows, but the grant version and
      # the door's own version survive, so the audit can still name the door.
      Ash.destroy!(door)

      {:ok, _view, html} = live(conn, ~p"/members/audit")

      assert html =~ "granted key access"
      assert html =~ "carol"
      assert html =~ "The Vault"
      refute html =~ door.id
    end
  end
end
