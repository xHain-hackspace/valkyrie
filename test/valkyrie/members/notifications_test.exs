defmodule Valkyrie.Members.NotificationsTest do
  use Valkyrie.DataCase, async: true

  import Swoosh.TestAssertions

  alias Valkyrie.Members.Notifications

  setup do
    ensure_key_targets()
    :ok
  end

  defp member(key_targets) do
    member_fixture(%{
      username: "alice",
      email: "member@example.com",
      key_targets: key_targets
    })
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
