defmodule Valkyrie.VersionTest do
  use ExUnit.Case, async: true

  test "version/0 returns a valid SemVer version" do
    assert {:ok, %Version{}} = Version.parse(Valkyrie.version())
  end
end
