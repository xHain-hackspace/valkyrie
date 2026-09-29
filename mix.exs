defmodule Valkyrie.MixProject do
  use Mix.Project

  def project do
    [
      app: :valkyrie,
      version: version(),
      elixir: "~> 1.15",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),
      compilers: [:phoenix_live_view] ++ Mix.compilers(),
      listeners: [Phoenix.CodeReloader],
      consolidate_protocols: Mix.env() != :dev
    ]
  end

  # Configuration for the OTP application.
  #
  # Type `mix help compile.app` for more information.
  def application do
    [
      mod: {Valkyrie.Application, []},
      extra_applications: [:logger, :runtime_tools, :ssh, :public_key]
    ]
  end

  def cli do
    [
      preferred_envs: [precommit: :test]
    ]
  end

  # The version comes from the latest `v*.*.*` git tag, or from the
  # `APP_VERSION` environment variable (set by the Docker build, which has no
  # git history). Commits since the tag go into the SemVer build metadata:
  #
  #     v0.6.0                  -> 0.6.0
  #     v0.6.0-4-g3156ab9       -> 0.6.0+4.g3156ab9
  #     v0.6.0-4-g3156ab9-dirty -> 0.6.0+4.g3156ab9.dirty
  #     3156ab9                 -> 0.0.0+g3156ab9
  defp version do
    case System.get_env("APP_VERSION", "") do
      "" -> git_describe()
      version -> version
    end
    |> normalize_version()
    |> tap(&Version.parse!/1)
  end

  defp git_describe do
    case System.cmd("git", ~w(describe --tags --match v[0-9]* --always --dirty),
           stderr_to_stdout: true
         ) do
      {output, 0} -> String.trim(output)
      _ -> nil
    end
  rescue
    _ -> nil
  end

  defp normalize_version(nil), do: "0.0.0-dev"

  defp normalize_version(raw) do
    case Regex.run(~r/^v?(\d+\.\d+\.\d+)(?:-(\d+)-(g[0-9a-f]+))?(-dirty)?$/, raw) do
      [_, version] -> version
      [_, version, "", "", "-dirty"] -> version <> "+dirty"
      [_, version, count, sha] -> "#{version}+#{count}.#{sha}"
      [_, version, count, sha, "-dirty"] -> "#{version}+#{count}.#{sha}.dirty"
      nil -> normalize_untagged(raw)
    end
  end

  defp normalize_untagged(raw) do
    case Regex.run(~r/^([0-9a-f]+)(-dirty)?$/, raw) do
      [_, sha] -> "0.0.0+g#{sha}"
      [_, sha, "-dirty"] -> "0.0.0+g#{sha}.dirty"
      nil -> raw
    end
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Specifies your project dependencies.
  #
  # Type `mix help deps` for examples and options.
  defp deps do
    [
      {:ash_archival, "~> 2.0"},
      {:picosat_elixir, "~> 0.2"},
      {:sourceror, "~> 1.8", only: [:dev, :test]},
      {:ash_paper_trail, "~> 0.5"},
      {:mishka_chelekom, "~> 0.0", only: [:dev]},
      {:live_debugger, "~> 0.4", only: [:dev]},
      {:ash_admin, "~> 0.13"},
      {:ash_authentication_phoenix, "~> 2.0"},
      {:ash_authentication, "~> 4.0"},
      {:ash_sqlite, "~> 0.2"},
      {:ash_phoenix, "~> 2.0"},
      {:ash, "~> 3.0"},
      {:igniter, "~> 0.6", only: [:dev, :test]},
      {:phoenix, "~> 1.8.1"},
      {:phoenix_ecto, "~> 4.5"},
      {:ecto_sql, "~> 3.13"},
      {:ecto_sqlite3, ">= 0.0.0"},
      {:phoenix_html, "~> 4.1"},
      {:phoenix_live_reload, "~> 1.2", only: :dev},
      {:phoenix_live_view, "~> 1.1.0"},
      {:lazy_html, ">= 0.1.0", only: :test},
      {:phoenix_live_dashboard, "~> 0.8.3"},
      {:esbuild, "~> 0.10", runtime: Mix.env() == :dev},
      {:tailwind, "~> 0.3", runtime: Mix.env() == :dev},
      {:heroicons,
       github: "tailwindlabs/heroicons",
       tag: "v2.2.0",
       sparse: "optimized",
       app: false,
       compile: false,
       depth: 1},
      {:swoosh, "~> 1.16"},
      {:req, "~> 0.5"},
      {:telemetry_metrics, "~> 1.0"},
      {:telemetry_metrics_prometheus_core, "~> 1.2"},
      {:telemetry_poller, "~> 1.0"},
      {:gettext, "~> 0.26"},
      {:jason, "~> 1.4"},
      {:dns_cluster, "~> 0.2.0"},
      {:bandit, "~> 1.5"},
      {:mint, "~> 1.0"},
      {:ex_crypto, "~> 0.10"},
      {:mua, "~> 0.2.0"},
      {:mail, "~> 0.5.2"},
      {:hackney, "~> 1.9"}
    ]
  end

  # Aliases are shortcuts or tasks specific to the current project.
  # For example, to install project dependencies and perform other setup tasks, run:
  #
  #     $ mix setup
  #
  # See the documentation for `Mix` for more info on aliases.
  defp aliases do
    [
      setup: ["deps.get", "ecto.setup", "assets.setup", "assets.build"],
      "ecto.setup": ["ecto.create", "ecto.migrate", "run priv/repo/seeds.exs"],
      "ecto.reset": ["ecto.drop", "ecto.setup"],
      test: ["ash.setup --quiet", "test"],
      "assets.setup": ["tailwind.install --if-missing", "esbuild.install --if-missing"],
      "assets.build": ["compile", "tailwind valkyrie", "esbuild valkyrie"],
      "assets.deploy": [
        "tailwind valkyrie --minify",
        "esbuild valkyrie --minify",
        "phx.digest"
      ],
      precommit: ["compile --warning-as-errors", "deps.unlock --unused", "format", "test"],
      "ash.setup": ["ash.setup", "run priv/repo/seeds.exs"]
    ]
  end
end
