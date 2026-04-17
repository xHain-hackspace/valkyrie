defmodule Valkyrie.AuthentikHelpers do
  @doc "Builds a raw Authentik API user map. Pass attrs to override any field."
  def user_fixture(attrs \\ %{}) do
    Map.merge(
      %{
        "username" => "testuser",
        "pk" => 1,
        "type" => "internal",
        "groups" => [],
        "attributes" => %{
          "ssh-key" => "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOn6J0bzZLnNNvMVDzyP63RNQjdT3BgBRZLm2wO+9sZl",
          "tree" => "birke"
        }
      },
      attrs
    )
  end

  @doc """
  Builds a paginated Authentik API response body.
  `next_page` is nil (no more pages) or an integer page number.
  """
  def page_response(users, next_page \\ nil) do
    %{
      "results" => users,
      "pagination" => %{
        "next" => next_page,
        "count" => length(users)
      }
    }
  end

  @doc "Registers a Req.Test stub that returns `response` as JSON for all Authentik requests."
  def stub_authentik(response) do
    Req.Test.stub(:valkyrie_authentik, fn conn ->
      Req.Test.json(conn, response)
    end)
  end
end
