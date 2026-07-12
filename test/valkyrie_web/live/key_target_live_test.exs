defmodule ValkyrieWeb.KeyTargetLiveTest do
  use ValkyrieWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Valkyrie.Members.KeyTarget
  alias Valkyrie.Members.Member

  defp door(attrs), do: key_target_fixture(attrs)

  defp target_slugs(member_id) do
    Member
    |> Ash.get!(member_id, authorize?: false, load: [:key_targets])
    |> Map.fetch!(:key_targets)
    |> Enum.map(& &1.slug)
  end

  describe "Index" do
    test "lists existing doors", %{conn: conn} do
      door(%{slug: "garage", name: "Garage"})

      {:ok, _view, html} = live(conn, ~p"/doors")

      assert html =~ "Doors"
      assert html =~ "garage"
      assert html =~ "Garage"
    end

    test "creates a new door", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/doors/new")

      view
      |> form("#key_target-form", key_target: %{slug: "garage", name: "Garage"})
      |> render_submit()

      assert_redirect(view, ~p"/doors")

      assert Enum.any?(Ash.read!(KeyTarget), &(&1.slug == "garage"))
    end

    test "creating a door grants it to all current keyholders when checked", %{conn: conn} do
      keyholder = member_fixture(%{username: "kh", key_targets: ["g16"]})
      non_keyholder = member_fixture(%{username: "nkh", xhain_account_id: 2, key_targets: []})

      {:ok, view, _html} = live(conn, ~p"/doors/new")

      view
      |> form("#key_target-form",
        key_target: %{slug: "garage", name: "Garage", grant_to_all_keyholders: "true"}
      )
      |> render_submit()

      assert_redirect(view, ~p"/doors")

      assert "garage" in target_slugs(keyholder.id)
      refute "garage" in target_slugs(non_keyholder.id)
    end

    test "creating a door grants no one when the option is unchecked", %{conn: conn} do
      keyholder = member_fixture(%{username: "kh", key_targets: ["g16"]})

      {:ok, view, _html} = live(conn, ~p"/doors/new")

      view
      |> form("#key_target-form",
        key_target: %{slug: "garage", name: "Garage", grant_to_all_keyholders: "false"}
      )
      |> render_submit()

      assert_redirect(view, ~p"/doors")

      refute "garage" in target_slugs(keyholder.id)
    end

    test "deletes a door from the list", %{conn: conn} do
      target = door(%{slug: "garage", name: "Garage"})

      {:ok, view, _html} = live(conn, ~p"/doors")

      assert view |> element("#key_targets-#{target.id}") |> has_element?()

      view |> element("#key_targets-#{target.id} button", "Delete") |> render_click()

      refute view |> element("#key_targets-#{target.id}") |> has_element?()
      refute Enum.any?(Ash.read!(KeyTarget), &(&1.id == target.id))
    end
  end

  describe "Edit" do
    test "changes the name and does not offer the immutable slug", %{conn: conn} do
      target = door(%{slug: "garage", name: "Garage"})

      {:ok, view, html} = live(conn, ~p"/doors/#{target.id}/edit")

      # Slug is immutable — the edit form must not expose a slug input.
      refute html =~ ~s(name="key_target[slug]")

      view
      |> form("#key_target-form", key_target: %{name: "Back Garage"})
      |> render_submit()

      assert_redirect(view, ~p"/doors")

      updated = Ash.get!(KeyTarget, target.id, authorize?: false)
      assert updated.name == "Back Garage"
      assert updated.slug == "garage"
    end
  end
end
