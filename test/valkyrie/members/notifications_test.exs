defmodule Valkyrie.Members.NotificationsTest do
  use Valkyrie.DataCase, async: true

  import Swoosh.TestAssertions

  alias Valkyrie.Members.Notifications

  @ssh_key "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOn6J0bzZLnNNvMVDzyP63RNQjdT3BgBRZLm2wO+9sZl"

  defp member(key_targets) do
    %{
      email: "member@example.com",
      username: "alice",
      ssh_public_key: @ssh_key,
      key_targets: key_targets
    }
  end

  test "skips sending when the member has no email" do
    assert :ok = Notifications.notify_ssh_key_changed(%{email: nil})
    assert_no_email_sent()
  end

  test "a keyholder is told the change takes effect on xDoor" do
    assert :ok = Notifications.notify_ssh_key_changed(member(["g16"]))

    assert_email_sent(fn email ->
      refute email.text_body =~ "not marked as a keyholder"
      assert email.text_body =~ "effective on xDoor"
    end)
  end

  test "a non-keyholder is told the change will not take effect" do
    assert :ok = Notifications.notify_ssh_key_changed(member([]))

    assert_email_sent(fn email ->
      assert email.text_body =~ "not marked as a keyholder"
    end)
  end
end
