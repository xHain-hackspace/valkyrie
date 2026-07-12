defmodule ValkyrieWeb.KeyTargetLiveTest do
  use ValkyrieWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Valkyrie.Members.KeyTarget

  defp door(attrs), do: Ash.create!(KeyTarget, attrs)

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
