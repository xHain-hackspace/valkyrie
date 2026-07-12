defmodule ValkyrieWeb.MemberLive.IndexTest do
  use ValkyrieWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Valkyrie.Members.Member
  alias Valkyrie.Members.SyncState

  setup do
    SyncState.finish_sync()
    :ok
  end

  describe "member list" do
    test "renders members on mount", %{conn: conn} do
      member_fixture(%{
        username: "alice",
        tree_name: "aloe",
        is_active: true,
        matrix_contact: "@alice:x-hain.de"
      })

      {:ok, _view, html} = live(conn, ~p"/members")

      assert html =~ "alice"
      assert html =~ "@alice:x-hain.de"
      assert not (html =~ "aloe")
    end

    test "only active members are shown by default", %{conn: conn} do
      member_fixture(%{username: "active-user", is_active: true})
      member_fixture(%{username: "inactive-user", xhain_account_id: 2, is_active: false})

      {:ok, _view, html} = live(conn, ~p"/members")

      assert html =~ "active-user"
      refute html =~ "inactive-user"
    end

    test "search by username filters results", %{conn: conn} do
      member_fixture(%{username: "alice", tree_name: "aloe", is_active: true})
      member_fixture(%{username: "bob", xhain_account_id: 2, tree_name: "birke", is_active: true})

      {:ok, view, _html} = live(conn, ~p"/members")

      html = render_change(view, "search", %{"search_query" => "alice"})

      assert html =~ "alice"
      refute html =~ "bob"
    end

    test "only keyholders filter shows only members with key access", %{conn: conn} do
      keyholder =
        member_fixture(%{username: "keyholder", key_targets: ["g16"], is_active: true})

      no_key =
        member_fixture(%{
          username: "no-key",
          xhain_account_id: 2,
          key_targets: [],
          is_active: true
        })

      {:ok, view, _html} = live(conn, ~p"/members")

      render_change(view, "filter_changed", %{
        "only_active_members" => "true",
        "only_inactive_members" => "false",
        "only_manual_entries" => "false",
        "only_keyholders" => "true"
      })

      assert has_element?(view, "#members-#{keyholder.id}")
      refute has_element?(view, "#members-#{no_key.id}")
    end

    test "only inactive members filter shows inactive members", %{conn: conn} do
      active = member_fixture(%{username: "active-user", is_active: true})

      inactive =
        member_fixture(%{username: "inactive-user", xhain_account_id: 2, is_active: false})

      {:ok, view, _html} = live(conn, ~p"/members")

      render_change(view, "filter_changed", %{
        "only_active_members" => "false",
        "only_inactive_members" => "true",
        "only_manual_entries" => "false",
        "only_keyholders" => "false"
      })

      assert has_element?(view, "#members-#{inactive.id}")
      refute has_element?(view, "#members-#{active.id}")
    end
  end

  describe "delete" do
    test "removes a manual entry from the list", %{conn: conn} do
      member =
        Ash.create!(Member, %{username: "alice", tree_name: "aloe"}, action: :create_manual_entry)

      {:ok, view, html} = live(conn, ~p"/members")

      assert html =~ "alice"

      render_click(view, "delete", %{"id" => member.id})

      refute render(view) =~ "alice"
    end

    test "archives the member in the database after delete", %{conn: conn} do
      member =
        Ash.create!(Member, %{username: "alice", tree_name: "aloe"}, action: :create_manual_entry)

      {:ok, view, _html} = live(conn, ~p"/members")

      render_click(view, "delete", %{"id" => member.id})

      assert Enum.empty?(Ash.read!(Member))
    end
  end

  describe "toggle_target" do
    test "grants access to a target", %{conn: conn} do
      member = member_fixture(%{username: "alice", key_targets: []})

      {:ok, view, _html} = live(conn, ~p"/members")

      view |> element("#kt-g16-#{member.id}") |> render_click()

      updated = Ash.get!(Member, member.id, authorize?: false)
      assert updated.key_targets == ["g16"]
    end

    test "revokes access to a target", %{conn: conn} do
      member = member_fixture(%{username: "alice", key_targets: ["g16", "g18"]})

      {:ok, view, _html} = live(conn, ~p"/members")

      view |> element("#kt-g16-#{member.id}") |> render_click()

      updated = Ash.get!(Member, member.id, authorize?: false)
      assert updated.key_targets == ["g18"]
    end
  end

  describe "toggle_all_targets" do
    test "grants all targets from an empty set", %{conn: conn} do
      member = member_fixture(%{username: "alice", key_targets: []})

      {:ok, view, _html} = live(conn, ~p"/members")

      view |> element("#kt-all-#{member.id}") |> render_click()

      updated = Ash.get!(Member, member.id, authorize?: false)
      assert Enum.sort(updated.key_targets) == ["g16", "g18", "g20"]
    end

    test "revokes all targets when the member already holds every one", %{conn: conn} do
      member = member_fixture(%{username: "alice", key_targets: ["g16", "g18", "g20"]})

      {:ok, view, _html} = live(conn, ~p"/members")

      view |> element("#kt-all-#{member.id}") |> render_click()

      updated = Ash.get!(Member, member.id, authorize?: false)
      assert updated.key_targets == []
    end

    test "grants all targets from a partial set", %{conn: conn} do
      member = member_fixture(%{username: "alice", key_targets: ["g16"]})

      {:ok, view, _html} = live(conn, ~p"/members")

      view |> element("#kt-all-#{member.id}") |> render_click()

      updated = Ash.get!(Member, member.id, authorize?: false)
      assert Enum.sort(updated.key_targets) == ["g16", "g18", "g20"]
    end

    test "the 'All' checkbox is derived from the member's targets", %{conn: conn} do
      full = member_fixture(%{username: "full", key_targets: ["g16", "g18", "g20"]})

      partial =
        member_fixture(%{username: "partial", xhain_account_id: 2, key_targets: ["g16"]})

      {:ok, view, _html} = live(conn, ~p"/members")

      assert has_element?(view, "input#kt-all-#{full.id}[checked]")
      refute has_element?(view, "input#kt-all-#{partial.id}[checked]")
    end
  end

  describe "sync_members" do
    test "shows sync in-progress UI when triggered", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/members")

      html = render_click(view, "sync_members", %{})

      assert html =~ "Syncing members from Authentik"
    end

    test "shows flash error when sync is already running", %{conn: conn} do
      :ok = SyncState.start_sync()

      {:ok, view, _html} = live(conn, ~p"/members")

      html = render_click(view, "sync_members", %{})

      assert html =~ "Sync is already in progress"
    end
  end
end
