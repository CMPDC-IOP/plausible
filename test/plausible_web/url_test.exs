defmodule PlausibleWeb.URLTest do
  use ExUnit.Case, async: true

  alias PlausibleWeb.URL

  test "paths use the configured base path" do
    assert URL.path([path: nil], "sites") == "/sites"
    assert URL.path([path: "/"], "/sites") == "/sites"
    assert URL.path([path: "/plausible/"], "/sites") == "/plausible/sites"
    assert URL.path([path: "/plausible"], "") == "/plausible/"
  end

  test "absolute URLs use the configured base path" do
    config = [scheme: "https", host: "example.com", path: "/plausible"]

    assert URL.base_url(config) == "https://example.com/plausible"

    assert URL.url(config, "auth/google/callback") ==
             "https://example.com/plausible/auth/google/callback"
  end
end
