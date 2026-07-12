defmodule Valkyrie.Members.Notifications do
  @moduledoc """
  Notification emails for member-related events.
  """

  require Logger

  import Swoosh.Email

  alias Valkyrie.Mailer

  def notify_ssh_key_changed(%{email: email}) when is_nil(email) or email == "" do
    Logger.info("Skipping SSH key change notification: no email on record")
    :ok
  end

  def notify_ssh_key_changed(%{
        email: email,
        username: username,
        ssh_public_key: ssh_key,
        key_targets: key_targets
      }) do
    build_ssh_key_changed_email(email, username, ssh_key, key_targets != [])
    |> Mailer.deliver()
    |> case do
      {:ok, _} ->
        :ok

      {:error, reason} ->
        Logger.warning(
          "Failed to send SSH key change notification to #{email}: #{inspect(reason)}"
        )

        {:error, reason}
    end
  end

  defp build_ssh_key_changed_email(to_email, username, new_ssh_key, has_key) do
    new()
    |> to(to_email)
    |> from({"xDoor", from_address()})
    |> reply_to({"xHain", "info@x-hain.de"})
    |> subject("Your SSH key has been updated")
    |> text_body("""
    Hello #{username},

    This is a notification that the SSH public key associated with your xHain account has been changed.

    #{if has_key do
      "The change will be effective on xDoor within the next hour."
    else
      "Your are not marked as a keyholder, so the change will not be effective on xDoor."
    end}

    New SSH public key: #{new_ssh_key}

    If you made this change yourself, you can ignore this message.
    If you did not make this change, please contact the xHain admins immediately.

    -- xDoor
    """)
  end

  defp from_address do
    Application.get_env(:valkyrie, :notification_from, "xdoor@x-hain.de")
  end
end
