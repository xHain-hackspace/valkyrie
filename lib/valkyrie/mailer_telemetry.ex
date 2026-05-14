defmodule Valkyrie.MailerTelemetry do
  @moduledoc """
  Logs Swoosh delivery events so mail problems are visible in dev and prod.
  """

  require Logger

  @events [
    [:swoosh, :deliver, :start],
    [:swoosh, :deliver, :stop],
    [:swoosh, :deliver, :exception]
  ]

  def attach do
    :telemetry.attach_many(
      "valkyrie-mailer-telemetry",
      @events,
      &__MODULE__.handle_event/4,
      nil
    )
  end

  def handle_event([:swoosh, :deliver, :start], _measurements, %{email: email}, _config) do
    Logger.debug("Mailer: delivering #{describe(email)}")
  end

  def handle_event(
        [:swoosh, :deliver, :stop],
        %{duration: duration},
        %{email: email} = meta,
        _config
      ) do
    ms = System.convert_time_unit(duration, :native, :millisecond)

    case meta do
      %{error: error} ->
        Logger.error("Mailer: delivery failed in #{ms}ms for #{describe(email)}: #{inspect(error)}")

      _ ->
        Logger.info("Mailer: delivered #{describe(email)} in #{ms}ms")
    end
  end

  def handle_event(
        [:swoosh, :deliver, :exception],
        %{duration: duration},
        %{email: email, kind: kind, reason: reason, stacktrace: stacktrace},
        _config
      ) do
    ms = System.convert_time_unit(duration, :native, :millisecond)

    Logger.error("""
    Mailer: delivery crashed in #{ms}ms for #{describe(email)}
    #{Exception.format(kind, reason, stacktrace)}
    """)
  end

  defp describe(%Swoosh.Email{to: to, subject: subject}) do
    "#{inspect(to)} subject=#{inspect(subject)}"
  end

  defp describe(_), do: "<unknown email>"
end
