defmodule ValkyrieWeb.MemberLive.FormTest do
  use ValkyrieWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Valkyrie.Members.Member

  describe "new member form" do
    test "renders an empty form", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/members/new")

      assert html =~ "New Member"
      assert html =~ "Username"
      assert html =~ "SSH Public Key"
      assert html =~ "Treename"
    end

    test "validates required fields on change", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/members/new")

      html =
        view
        |> form("#member-form", member: %{username: "", tree_name: ""})
        |> render_change()

      assert html =~ "required"
    end

    test "creates a manual entry and redirects on valid submit", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/members/new")

      view
      |> form("#member-form",
        member: %{
          username: "alice",
          tree_name: "aloe",
          ssh_public_key: valid_ssh_key(),
          has_key: "true"
        }
      )
      |> render_submit()

      assert_redirect(view, ~p"/members")

      [member] = Ash.read!(Member)
      assert member.username == "alice"
      assert member.is_manual_entry == true
    end
  end

  describe "edit member form" do
    test "renders existing member data", %{conn: conn} do
      member =
        Ash.create!(
          Member,
          %{username: "alice", tree_name: "aloe", ssh_public_key: valid_ssh_key()},
          action: :create_manual_entry
        )

      {:ok, _view, html} = live(conn, ~p"/members/#{member.id}/edit")

      assert html =~ "Edit Member"
      assert html =~ "alice"
      assert html =~ "aloe"
    end

    test "updates the member and redirects on valid submit", %{conn: conn} do
      member =
        Ash.create!(Member, %{username: "alice", tree_name: "aloe"},
          action: :create_manual_entry
        )

      {:ok, view, _html} = live(conn, ~p"/members/#{member.id}/edit")

      view
      |> form("#member-form", member: %{tree_name: "birke"})
      |> render_submit()

      assert_redirect(view, ~p"/members")

      updated = Ash.get!(Member, member.id, authorize?: false)
      assert updated.tree_name == "birke"
    end
  end
end
