defmodule ValkyrieWeb.AuditLive.IndexTest do
  use ValkyrieWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias ValkyrieWeb.AuditLive.Index

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

  describe "audit log rendering" do
    test "renders a key_targets change as an explicit diff", %{conn: conn} do
      member = member_fixture(%{username: "alice", key_targets: ["g16", "g20"]})

      Ash.update!(member, %{key_targets: ["g16", "g18"]}, action: :change_keyholder_status)

      {:ok, _view, html} = live(conn, ~p"/members/audit")

      assert html =~ "changed key_targets: added g18; removed g20"
    end
  end
end
