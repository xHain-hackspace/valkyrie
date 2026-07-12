defmodule ValkyrieWeb.LiveUserAuthTest do
  use ExUnit.Case, async: true

  alias ValkyrieWeb.LiveUserAuth

  defp socket(current_user) do
    %Phoenix.LiveView.Socket{assigns: %{current_user: current_user, __changed__: %{}}}
  end

  describe "on_mount(:live_admin_required)" do
    test "an admin user is allowed through" do
      assert {:cont, _socket} =
               LiveUserAuth.on_mount(:live_admin_required, %{}, %{}, socket(%{is_admin: true}))
    end

    test "a non-admin user is halted and redirected home" do
      assert {:halt, socket} =
               LiveUserAuth.on_mount(:live_admin_required, %{}, %{}, socket(%{is_admin: false}))

      assert {:redirect, %{to: "/"}} = socket.redirected
    end

    test "an anonymous visitor is halted and redirected to sign-in" do
      assert {:halt, socket} =
               LiveUserAuth.on_mount(:live_admin_required, %{}, %{}, socket(nil))

      assert {:redirect, %{to: "/sign-in"}} = socket.redirected
    end
  end
end
