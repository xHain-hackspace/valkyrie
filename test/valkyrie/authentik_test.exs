defmodule Valkyrie.AuthentikTest do
  use ExUnit.Case, async: true

  import Valkyrie.AuthentikHelpers

  alias Valkyrie.Authentik
  alias Valkyrie.Authentik.XHainAccount

  describe "get_all_users/1" do
    test "maps API response to XHainAccount structs" do
      user =
        user_fixture(%{
          "username" => "alice",
          "pk" => 42,
          "groups" => ["group-uuid-1"],
          "attributes" => %{"ssh-key" => "ssh-ed25519 AAAA...", "tree" => "aloe"}
        })

      stub_authentik(page_response([user]))

      assert {:ok, [account]} = Authentik.get_all_users()

      assert %XHainAccount{
               username: "alice",
               xhain_account_id: 42,
               ssh_public_key: "ssh-ed25519 AAAA...",
               tree_name: "aloe",
               groups: ["group-uuid-1"]
             } = account
    end

    test "fetches and concatenates multiple pages" do
      page1_user = user_fixture(%{"username" => "alice", "pk" => 1})
      page2_user = user_fixture(%{"username" => "bob", "pk" => 2})

      Req.Test.expect(:valkyrie_authentik, fn conn ->
        Req.Test.json(conn, page_response([page1_user], 2))
      end)

      Req.Test.expect(:valkyrie_authentik, fn conn ->
        Req.Test.json(conn, page_response([page2_user]))
      end)

      assert {:ok, accounts} = Authentik.get_all_users()
      assert length(accounts) == 2
      assert Enum.map(accounts, & &1.username) == ["alice", "bob"]
    end

    test "filters out service users" do
      normal_user = user_fixture(%{"username" => "alice", "type" => "internal"})
      service_user = user_fixture(%{"username" => "ci-bot", "type" => "service_account"})

      stub_authentik(page_response([normal_user, service_user]))

      assert {:ok, accounts} = Authentik.get_all_users()
      assert length(accounts) == 1
      assert hd(accounts).username == "alice"
    end

    test "calls progress callback with page info" do
      stub_authentik(page_response([user_fixture()]))

      agent = start_link_supervised!({Agent, fn -> [] end})

      callback = fn update ->
        Agent.update(agent, fn acc -> [update | acc] end)
      end

      assert {:ok, _} = Authentik.get_all_users(callback)

      updates = Agent.get(agent, & &1)
      assert length(updates) == 1

      assert [%{page: 1, total_pages: 1, users_fetched: 1, status: :in_progress}] = updates
    end

    test "returns {:ok, []} for empty results" do
      stub_authentik(page_response([]))

      assert {:ok, []} = Authentik.get_all_users()
    end

    test "returns error tuple when API responds with non-200 status" do
      Req.Test.stub(:valkyrie_authentik, fn conn ->
        Plug.Conn.send_resp(conn, 403, "Forbidden")
      end)

      assert {:error, "API returned status 403"} = Authentik.get_all_users()
    end

    test "returns error tuple on network failure" do
      Req.Test.stub(:valkyrie_authentik, fn conn ->
        Req.Test.transport_error(conn, :econnrefused)
      end)

      assert {:error, _reason} = Authentik.get_all_users()
    end

    test "maps missing ssh-key attribute to empty string" do
      user = user_fixture(%{"attributes" => %{"tree" => "eiche"}})

      stub_authentik(page_response([user]))

      assert {:ok, [account]} = Authentik.get_all_users()
      assert account.ssh_public_key == ""
    end

    test "maps missing tree attribute to nil" do
      user = user_fixture(%{"attributes" => %{"ssh-key" => "ssh-ed25519 AAAA..."}})

      stub_authentik(page_response([user]))

      assert {:ok, [account]} = Authentik.get_all_users()
      assert account.tree_name == nil
    end
  end
end
