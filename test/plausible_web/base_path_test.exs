defmodule PlausibleWeb.BasePathTest do
  # `PlausibleWeb.Endpoint.script_name/0` is read from :persistent_term when the
  # endpoint starts, so it cannot be changed for a single test. `PlausibleWeb.URL`
  # reads the endpoint's `:url` config (cached in ETS by Phoenix), which is what
  # these tests patch and restore.
  use PlausibleWeb.ConnCase, async: false

  alias PlausibleWeb.Endpoint

  setup do
    [{:url, url_config}] = :ets.lookup(Endpoint, :url)
    :ets.insert(Endpoint, {:url, Keyword.put(url_config, :path, "/plausible")})

    on_exit(fn -> :ets.insert(Endpoint, {:url, url_config}) end)
  end

  describe "put_script_name/2" do
    test "prefixes root-relative redirects" do
      conn = redirect_through(["plausible"], "/login")

      assert Plug.Conn.get_resp_header(conn, "location") == ["/plausible/login"]
      assert conn.script_name == ["plausible"]
    end

    test "keeps redirects that already carry the base path" do
      conn = redirect_through(["plausible"], "/plausible/login")

      assert Plug.Conn.get_resp_header(conn, "location") == ["/plausible/login"]
    end

    test "leaves absolute and protocol-relative redirects alone" do
      for location <- ["https://example.com/login", "//example.com/login"] do
        conn = redirect_through(["plausible"], location)

        assert Plug.Conn.get_resp_header(conn, "location") == [location]
      end
    end

    test "does nothing without a configured script name" do
      conn = redirect_through([], "/login")

      assert Plug.Conn.get_resp_header(conn, "location") == ["/login"]
      assert conn.script_name == []
    end
  end

  describe "absolute URLs" do
    test "OAuth authorization server metadata uses the base path", %{conn: conn} do
      base_url = PlausibleWeb.URL.base_url()
      assert String.ends_with?(base_url, "/plausible")

      resp = conn |> get("/.well-known/oauth-authorization-server") |> json_response(200)

      assert resp["issuer"] == base_url
      assert resp["authorization_endpoint"] == base_url <> "/login/oauth/authorize"
      assert resp["token_endpoint"] == base_url <> "/login/oauth/token"
    end

    test "protected resource metadata uses the base path", %{conn: conn} do
      base_url = PlausibleWeb.URL.base_url()

      resp = conn |> get("/.well-known/oauth-protected-resource/mcp") |> json_response(200)

      assert resp["resource"] == base_url <> "/mcp"
      assert resp["authorization_servers"] == [base_url]
    end

    test "the OAuth challenge points at the base-path metadata" do
      metadata_url =
        PlausibleWeb.URL.base_url() <> "/.well-known/oauth-protected-resource/mcp"

      challenge =
        PlausibleWeb.Plugs.AuthorizeOAuthAPI.challenge(
          Plausible.OAuth.ProtectedResources.mcp(),
          "sites:read:*"
        )

      assert challenge =~ metadata_url
    end

    test "the resource lookup matches the base-path URL" do
      resource_url = PlausibleWeb.URL.base_url() <> "/mcp"

      assert Plausible.OAuth.ProtectedResources.get_by_url(resource_url) ==
               {:ok, Plausible.OAuth.ProtectedResources.mcp()}
    end
  end

  defp redirect_through(script_name, location) do
    Plug.Test.conn(:get, "/")
    |> Plug.Conn.put_resp_header("location", location)
    |> Endpoint.put_script_name(script_name)
    |> Plug.Conn.send_resp(302, "")
  end
end
