defmodule PlausibleWeb.SitePathIntegrationTest do
  use PlausibleWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  setup [:create_user, :log_in]

  setup %{user: user} do
    %{site: new_site(owner: user, domain: "example.com/docs/api")}
  end

  test "dashboard resolves the site token and keeps the real domain in its data", %{
    conn: conn,
    site: site
  } do
    conn = get(conn, "/example.com~docs~api")
    html = html_response(conn, 200)

    assert conn.assigns.site.id == site.id
    assert text_of_attr(html, "#stats-react-container", "data-domain") == site.domain
  end

  test "settings forms target the same site with an encoded path", %{conn: conn, site: site} do
    conn = get(conn, "/example.com~docs~api/settings/general")
    html = html_response(conn, 200)

    assert conn.assigns.site.id == site.id
    assert element_exists?(html, ~s|form[action="/example.com~docs~api/settings"]|)
    assert element_exists?(html, ~s|a[href="/example.com~docs~api/change-domain"]|)
  end

  test "internal API authorizes the decoded site even with a conflicting query domain", %{
    conn: conn,
    site: site
  } do
    conn = get(conn, "/api/stats/example.com~docs~api/current-visitors?domain=other.example")

    assert json_response(conn, 200)
    assert conn.assigns.site.id == site.id
    assert conn.path_params["domain"] == site.domain
  end

  test "encoded paths do not grant access to another user's site", %{conn: conn} do
    new_site(domain: "other.example/docs")

    assert conn |> get("/other.example~docs/settings/general") |> html_response(404)
  end

  test "shared links use safe tokens and resolve the real site", %{site: site} do
    link = insert(:shared_link, site: site)
    url = Plausible.Sites.shared_link_url(site, link)

    assert url =~ "/share/example.com~docs~api?auth="

    conn = get(build_conn(), URI.parse(url).path <> "?auth=" <> link.slug)
    assert html_response(conn, 200)
    assert conn.assigns.site.id == site.id
  end

  test "connected change-domain LiveView resolves the token", %{conn: conn, site: site} do
    {:ok, view, html} = live(conn, "/example.com~docs~api/change-domain")

    assert html =~ "Change your website domain"

    html = view |> element("form") |> render_submit(%{site: %{domain: site.domain}})
    assert html =~ "New domain must be different than the current one"
  end

  @tag :ce_build_only
  test "connected installation LiveView preserves the true tracking domain", %{
    conn: conn,
    site: site
  } do
    {:ok, view, html} = live(conn, "/example.com~docs~api/installation")

    assert html =~ site.domain

    view
    |> element("form[phx-submit='submit']")
    |> render_submit(%{"tracker_script_configuration" => %{"installation_type" => "manual"}})

    assert_redirect(view, "/example.com~docs~api")
  end
end
