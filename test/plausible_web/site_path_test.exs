defmodule PlausibleWeb.SitePathTest do
  use ExUnit.Case, async: true

  alias PlausibleWeb.SitePath

  defmodule Echo do
    def init(opts), do: opts
    def call(conn, _opts), do: Plug.Conn.send_resp(conn, 200, "ok")
  end

  defmodule Router do
    use Phoenix.Router

    pipeline :site do
      plug :fetch_query_params
      plug PlausibleWeb.Plugs.DecodeSiteDomain
    end

    scope "/" do
      pipe_through :site
      get "/:domain/settings", Echo, :show
      get "/api/stats/:domain/current-visitors", Echo, :show
      get "/share/:domain/*path", Echo, :show
      get "/api/v1/sites/:site_id", Echo, :show
      post "/event", Echo, :show
    end
  end

  test "site path encoding preserves domain identity through URI normalization" do
    for domain <- ["example.com", "example.com/docs", "例子.com/docs/api", "example.com//docs/"] do
      segment = SitePath.encode_segment(domain)
      refute segment =~ "/"
      refute segment =~ "%2F"
      assert segment |> URI.decode() |> SitePath.decode() == domain
    end

    assert SitePath.encode_segment("example.com/docs/api") == "example.com~docs~api"
  end

  test "routes decode only the site parameter after matching" do
    for path <- [
          "/example.com~docs~api/settings",
          "/api/stats/example.com~docs~api/current-visitors",
          "/share/example.com~docs~api/pages"
        ] do
      conn =
        Plug.Test.conn(:get, path <> "?domain=other.example&filter=a~b")
        |> Router.call(Router.init([]))

      assert conn.status == 200
      assert conn.path_params["domain"] == "example.com/docs/api"
      assert conn.params["domain"] == "example.com/docs/api"
      assert conn.params["filter"] == "a~b"
      assert conn.request_path == path
      assert "example.com~docs~api" in conn.path_info
    end
  end

  test "legacy escaped slashes still work when preserved by the proxy" do
    conn =
      Plug.Test.conn(:get, "/example.com%2Fdocs/settings")
      |> Router.call(Router.init([]))

    assert conn.path_params["domain"] == "example.com/docs"
  end

  test "public API site path parameters decode before authorization" do
    conn =
      Plug.Test.conn(:get, "/api/v1/sites/example.com~docs?site_id=other.example")
      |> Router.call(Router.init([]))

    assert conn.path_params["site_id"] == "example.com/docs"
    assert conn.params["site_id"] == "example.com/docs"
  end

  test "query and body domains are not path tokens" do
    conn =
      Plug.Test.conn(:post, "/event?site_id=example.com~docs", %{"domain" => "example.com~docs"})
      |> Router.call(Router.init([]))

    assert conn.params["domain"] == "example.com~docs"
    assert conn.params["site_id"] == "example.com~docs"
  end

  test "Phoenix links keep the base path, site token and query values separate" do
    conn = %{Plug.Test.conn(:get, "/") | script_name: ["plausible"]}
    domain = SitePath.encode("example.com/docs/api")

    assert PlausibleWeb.Router.Helpers.site_path(conn, :settings_general, domain) ==
             "/plausible/example.com~docs~api/settings/general"

    assert PlausibleWeb.Router.Helpers.stats_path(conn, :shared_link, domain, [], auth: "a/b") ==
             "/plausible/share/example.com~docs~api/?auth=a%2Fb"
  end

  test "favicon path tokens resolve to the original site's subdirectory" do
    test_pid = self()

    fetcher = fn url ->
      send(test_pid, {:fetch, url})

      if url == "https://example.com/docs/api/favicon.ico" do
        {:ok,
         Req.Response.new(status: 200, headers: %{"content-type" => "image/x-icon"}, body: "icon")}
      else
        {:ok, Req.Response.new(status: 404)}
      end
    end

    conn =
      Plug.Test.conn(:get, "/favicon/sources/example.com~docs~api")
      |> PlausibleWeb.Favicon.call(
        favicon_domains: %{},
        favicon_fetcher: fetcher,
        cache_name: nil
      )

    assert conn.status == 200
    assert conn.resp_body == "icon"
    assert_receive {:fetch, "https://example.com/docs/api/"}
    assert_receive {:fetch, "https://example.com/docs/api/favicon.ico"}
  end
end
