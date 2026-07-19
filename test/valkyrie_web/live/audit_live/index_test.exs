defmodule ValkyrieWeb.AuditLive.IndexTest do
  use ValkyrieWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Valkyrie.Members
  alias Valkyrie.Members.KeyTargets
  alias Valkyrie.Versions.ChangeFormatter

  defp target_id(slug), do: Enum.find(KeyTargets.all(), &(&1.slug == slug)).id

  describe "format_change/2" do
    test "renders scalar from/to changes" do
      assert ChangeFormatter.format_change("tree_name", %{"from" => "aloe", "to" => "birke"}) ==
               "changed tree_name from aloe to birke"
    end

    test "renders a scalar set (create) with an empty from" do
      assert ChangeFormatter.format_change("username", %{"to" => "alice"}) ==
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

      assert ChangeFormatter.format_change("key_targets", value) ==
               "changed key_targets: added g18; removed g20"
    end

    test "renders an array create with only additions" do
      value = %{
        "to" => [
          %{"added" => "g16", "index" => %{"to" => 0}},
          %{"added" => "g20", "index" => %{"to" => 1}}
        ]
      }

      assert ChangeFormatter.format_change("key_targets", value) ==
               "changed key_targets: added g16, g20"
    end

    test "skips unchanged attributes" do
      assert ChangeFormatter.format_change("tree_name", %{"unchanged" => "aloe"}) == ""

      unchanged_array = %{
        "unchanged" => [%{"index" => %{"unchanged" => 0}, "unchanged" => "g16"}]
      }

      assert ChangeFormatter.format_change("key_targets", unchanged_array) == ""
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
      # More users than the 100-per-page limit, so the oldest lands on a later
      # page. Each user also emits a member-create version, so the combined feed
      # holds well over one page regardless of exact per-user row count.
      for i <- 1..120 do
        n = String.pad_leading(to_string(i), 3, "0")

        %{username: "user#{n}", xhain_account_id: 100 + i, key_targets: []}
        |> member_fixture()
        |> Members.change_keyholder_status(%{key_target_ids: [target_id("g16")]})
      end

      {:ok, view, html} = live(conn, ~p"/members/audit")

      # Page 1 = newest; the oldest user is not here.
      assert html =~ "user120"
      refute html =~ "user001"

      # Page forward via real SQL offsets (previously capped) until the oldest
      # entry surfaces — proof deep pages are reachable.
      found =
        Enum.reduce_while(1..20, false, fn _, _ ->
          page = render_hook(view, "pagination", %{"action" => "next"})
          if page =~ "user001", do: {:halt, true}, else: {:cont, false}
        end)

      assert found, "paging forward never reached the oldest entry (user001)"
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
