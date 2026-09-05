defmodule PlausibleWeb.Favicon do
  @referer_domains_file "priv/referer_favicon_domains.json"
  @cache_name :favicon
  @fallback_favicon_paths ~w(favicon.ico favicon.png)
  @success_ttl :timer.hours(24)
  @negative_ttl :timer.hours(1)
  @max_favicon_size 2_000_000
  @default_content_type "image/x-icon"
  @browser_cache_control "no-store"

  @moduledoc """
  A Plug that resolves favicon images and returns them to the Plausible frontend.

  Site pages are inspected for a declared favicon before checking the conventional
  `favicon.ico` and `favicon.png` paths and falling back to DuckDuckGo. Resolved
  responses are cached internally so the server does not repeat external probes
  on every page load. Browser caching is disabled so fixes take effect without
  manually versioning the endpoint URL.

  The proxying is there so we can reduce the number of third-party domains that
  the browser clients need to connect to. Our goal is to have 0 third-party domain
  connections on the website for privacy reasons.

  This module also maps between categorized sources and their respective URLs for favicons.
  What does that mean exactly? During ingestion we use `PlausibleWeb.RefInspector.parse/1` to
  categorize our referrer sources like so:

  google.com -> Google
  google.co.uk -> Google
  google.com.au -> Google

  So when we show Google as a source in the dashboard, the request to this plug will come as:
  https://plausible/io/favicon/sources/Google

  Now, when we want to show a favicon for Google, we need to convert Google -> google.com or
  some other hostname owned by Google:
  https://icons.duckduckgo.com/ip3/google.com.ico

  The mapping from source category -> source hostname is stored in "#{@referer_domains_file}" and
  managed by `Mix.Tasks.GenerateReferrerFavicons.run/1`
  """
  import Plug.Conn
  alias Plausible.HTTPClient

  @source_placeholder_icon_location "priv/link_favicon.svg"
  @source_placeholder_icon File.read!(@source_placeholder_icon_location)
  @external_resource @source_placeholder_icon_location

  @source_dark_placeholder_icon_location "priv/link_favicon_dark.svg"
  @source_dark_placeholder_icon File.read!(@source_dark_placeholder_icon_location)
  @external_resource @source_dark_placeholder_icon_location

  @site_placeholder_icon_location "priv/site_favicon_placeholder.svg"
  @site_placeholder_icon File.read!(@site_placeholder_icon_location)
  @external_resource @site_placeholder_icon_location

  @site_dark_placeholder_icon_location "priv/site_favicon_placeholder_dark.svg"
  @site_dark_placeholder_icon File.read!(@site_dark_placeholder_icon_location)
  @external_resource @site_dark_placeholder_icon_location
  @custom_icons %{
    "Brave" => "search.brave.com",
    "Kagi" => "kagi.com",
    "Sogou" => "sogou.com",
    "Wikipedia" => "en.wikipedia.org",
    "Discord" => "discord.com",
    "Perplexity" => "perplexity.ai",
    "Microsoft Teams" => "microsoft.com",
    "LinkedIn" => "linkedin.com",
    "Linktree" => "linktr.ee",
    "Bluesky" => "bsky.app",
    "Mastodon" => "mastodon.social",
    "Google Gemini" => "gemini.google.com",
    "ChatGPT" => "chatgpt.com",
    "Claude" => "claude.ai",
    "Phind" => "phind.com",
    "DeepSeek" => "deepseek.com",
    "Microsoft Copilot" => "copilot.com",
    "Grok" => "grok.com",
    "X (Twitter)" => "x.com",
    "Microsoft 365" => "office.com"
  }

  def init(_) do
    domains =
      File.read!(Application.app_dir(:plausible, @referer_domains_file))
      |> Jason.decode!()
      |> Map.merge(@custom_icons)

    [
      favicon_domains: domains,
      favicon_fetcher: &Plausible.SSRF.get/1,
      trusted_hosts: :runtime,
      cache_name: @cache_name
    ]
  end

  @ddg_broken_icon <<137, 80, 78, 71, 13, 10, 26, 10>>
  @doc """
  Resolves a favicon from the configured site path and then the DuckDuckGo
  favicon service.

  ## Placeholder

  Cases where we show a placeholder icon instead:

  1. In case of network error to DuckDuckGo
  2. In case of non-2xx status code from DuckDuckGo
  3. In case of broken image response body from DuckDuckGo

  I'm not sure why DDG sometimes returns a broken PNG image in their response
  but we filter that out.  When the icon request fails, we show a placeholder
  favicon instead. The placeholder is an svg from [https://heroicons.com/](https://heroicons.com/).

  There are two placeholders, and `?placeholder=` picks one:

  - `source` is `#{@source_placeholder_icon_location}`, a plain
    link icon for the referrer rows in the reports.
  - `site` is `#{@site_placeholder_icon_location}`, a globe on a rounded grey
    background, for the rows that list sites.

  `?ui-mode=light|dark` picks the colours and defaults to `light`. Each
  placeholder has its own dark drawing, `#{@source_dark_placeholder_icon_location}`
  and `#{@site_dark_placeholder_icon_location}`. An SVG served as an image
  cannot see the `dark` class on the page, so the caller must say which mode it
  needs.

  DuckDuckGo favicon service has some issues with [SVG favicons](https://css-tricks.com/svg-favicons-and-all-the-fun-things-we-can-do-with-them/).
  For some reason, they return them with `content-type=image/x-icon` whereas SVG
  icons should be returned with `content-type=image/svg+xml`. This Plug detects
  when the response body starts with `<svg` and will override the `Content-Type`
  to correct it.

  ## Preventing XSS vulnerabilities

  SVGs may contain `<script>` tags, and as these SVGs come from external
  sources, we need to prevent untrusted code from running on the browser.

  - This Plug sets a strict `Content-Security-Policy` header telling the browser
    not to run scripts.

  - This Plug sets `Content-Disposition=attachment` to prevent the SVG from
    rendering when navigating to `/favicon/sources/:domain` directly.

  - Browsers do not execute scripts from `<img>` tags, therefore it is safe to
    use `<img src="https://plausible.io/favicon/sources/dummy.site"></img>`

  """
  def call(conn, opts) do
    favicon_domains = Keyword.fetch!(opts, :favicon_domains)
    favicon_fetcher = Keyword.get(opts, :favicon_fetcher, &Plausible.SSRF.get/1)

    trusted_favicon_fetcher =
      Keyword.get(opts, :trusted_favicon_fetcher, &__MODULE__.trusted_get/2)

    trusted_hosts =
      case Keyword.get(opts, :trusted_hosts, :runtime) do
        :runtime ->
          Application.get_env(:plausible, __MODULE__, []) |> Keyword.get(:trusted_hosts, [])

        trusted_hosts ->
          trusted_hosts
      end

    cache_name = Keyword.get(opts, :cache_name, @cache_name)

    case conn.request_path do
      "/favicon/placeholders/" <> name ->
        send_placeholder(conn, name)

      "/favicon/sources/" <> domain ->
        domain = domain |> URI.decode_www_form() |> PlausibleWeb.SitePath.decode()

        case cached_favicon(
               domain,
               favicon_domains,
               favicon_fetcher,
               trusted_favicon_fetcher,
               trusted_hosts,
               cache_name
             ) do
          nil -> send_placeholder(conn)
          response -> send_favicon(response, conn)
        end

      _ ->
        conn
    end
  end

  defp send_placeholder(conn, name \\ nil) do
    conn = fetch_query_params(conn)
    name = name || conn.query_params["placeholder"]

    conn
    |> put_resp_content_type("image/svg+xml")
    |> put_resp_header("cache-control", "public, max-age=2592000")
    |> send_resp(200, placeholder_icon(name, conn.query_params["ui-mode"]))
    |> halt
  end

  defp placeholder_icon("site", "dark"), do: @site_dark_placeholder_icon
  defp placeholder_icon("site", _ui_mode), do: @site_placeholder_icon
  defp placeholder_icon(_source, "dark"), do: @source_dark_placeholder_icon
  defp placeholder_icon(_source, _ui_mode), do: @source_placeholder_icon

  defp cached_favicon(
         domain,
         favicon_domains,
         favicon_fetcher,
         trusted_favicon_fetcher,
         trusted_hosts,
         cache_name
       ) do
    source_domain = Map.get(favicon_domains, domain, domain)

    resolver = fn ->
      resolve_favicon(source_domain, favicon_fetcher, trusted_favicon_fetcher, trusted_hosts)
    end

    if cache_available?(cache_name) do
      Plausible.Cache.Adapter.get(cache_name, source_domain, fn ->
        case resolver.() do
          nil -> %ConCache.Item{value: nil, ttl: @negative_ttl}
          response -> %ConCache.Item{value: response, ttl: response.ttl}
        end
      end)
    else
      resolver.()
    end
  end

  defp cache_available?(cache_name) when is_atom(cache_name),
    do: is_pid(Process.whereis(cache_name))

  defp cache_available?(_cache_name), do: false

  defp resolve_favicon(domain, favicon_fetcher, trusted_favicon_fetcher, trusted_hosts) do
    case site_uri(domain) do
      %URI{host: host} = uri when is_binary(host) ->
        host = String.downcase(host)

        fetcher =
          if host in trusted_hosts do
            fn url -> trusted_favicon_fetcher.(url, host) end
          else
            favicon_fetcher
          end

        discover_favicon(uri, fetcher) || fetch_duckduckgo_favicon(domain)

      _ ->
        fetch_duckduckgo_favicon(domain)
    end
  end

  defp discover_favicon(uri, fetcher) do
    page_uri = page_uri(uri)

    sources =
      page_favicon_sources(page_uri, fetcher) ++ fallback_favicon_sources(uri)

    sources
    |> Enum.uniq()
    |> Enum.find_value(&fetch_favicon(&1, fetcher))
  end

  defp page_favicon_sources(page_uri, fetcher) do
    case fetcher.(URI.to_string(page_uri)) do
      {:ok, %Req.Response{status: status, body: body} = response}
      when status in 200..299 and is_binary(body) and byte_size(body) <= @max_favicon_size ->
        if html_response?(response) do
          body
          |> LazyHTML.from_document()
          |> LazyHTML.query("link[rel][href]")
          |> Enum.filter(&icon_link?/1)
          |> Enum.flat_map(&LazyHTML.attribute(&1, "href"))
          |> Enum.map(&same_host_https_url(page_uri, &1))
          |> Enum.reject(&is_nil/1)
        else
          []
        end

      _ ->
        []
    end
  rescue
    _ -> []
  end

  defp icon_link?(link) do
    link
    |> LazyHTML.attribute("rel")
    |> Enum.any?(fn rel ->
      rel
      |> String.downcase()
      |> String.split()
      |> Enum.member?("icon")
    end)
  end

  defp same_host_https_url(page_uri, href) do
    uri = URI.merge(page_uri, href)

    if uri.scheme == "https" and String.downcase(uri.host || "") == String.downcase(page_uri.host) and
         uri.port in [nil, 443] do
      URI.to_string(%{uri | fragment: nil})
    end
  rescue
    _ -> nil
  end

  defp fallback_favicon_sources(%URI{host: host, path: path}) do
    path = String.trim_trailing(path || "", "/")
    prefixes = if path == "", do: [""], else: [path, ""]

    for prefix <- prefixes, favicon_path <- @fallback_favicon_paths do
      "https://#{host}#{prefix}/#{favicon_path}"
    end
  end

  defp fetch_favicon(url, fetcher) do
    case fetcher.(url) do
      {:ok, %Req.Response{status: status, body: body} = response}
      when status in 200..299 and is_binary(body) ->
        if valid_favicon?(response, body) do
          content_type = response_content_type(response)

          %{
            body: body,
            content_type: content_type,
            secure?: svg_content_type?(content_type),
            ttl: @success_ttl
          }
        end

      _ ->
        nil
    end
  rescue
    _ -> nil
  end

  defp valid_favicon?(response, body) do
    byte_size(body) > 0 and byte_size(body) <= @max_favicon_size and
      case Req.Response.get_header(response, "content-type") do
        [] -> true
        [content_type | _] -> String.starts_with?(String.downcase(content_type), "image/")
      end
  end

  defp html_response?(response) do
    case Req.Response.get_header(response, "content-type") do
      [] -> true
      headers -> Enum.any?(headers, &String.starts_with?(String.downcase(&1), "text/html"))
    end
  end

  defp site_uri(domain) do
    case URI.parse("https://#{domain}") do
      %URI{scheme: "https", host: host, port: port} = uri
      when is_binary(host) and host != "" and port in [nil, 443] ->
        %{uri | query: nil, fragment: nil}

      _ ->
        nil
    end
  end

  defp page_uri(uri) do
    path = uri.path || ""
    path = if path == "" or String.ends_with?(path, "/"), do: path, else: path <> "/"
    %{uri | path: path}
  end

  @doc false
  def trusted_get(url, trusted_host),
    do: Plausible.SSRF.get(url, trusted_hosts: [trusted_host], receive_timeout: 5_000)

  defp fetch_duckduckgo_favicon(domain) do
    hostname = domain |> String.split("/", parts: 2) |> hd()

    case HTTPClient.impl().get("https://icons.duckduckgo.com/ip3/#{hostname}.ico") do
      {:ok, %Finch.Response{status: 200, body: body, headers: headers}}
      when is_binary(body) and body != @ddg_broken_icon ->
        content_type = ddg_content_type(body, headers)

        %{
          body: body,
          content_type: content_type,
          secure?: svg_content_type?(content_type),
          ttl: @success_ttl
        }

      _ ->
        nil
    end
  end

  defp response_content_type(response) do
    case Req.Response.get_header(response, "content-type") do
      [content_type | _] -> content_type
      [] -> @default_content_type
    end
  end

  defp ddg_content_type(body, headers) do
    content_type = header_value(headers, "content-type") || @default_content_type

    if String.starts_with?(body, "<svg"),
      do: "image/svg+xml; charset=utf-8",
      else: content_type
  end

  defp svg_content_type?(content_type),
    do: String.starts_with?(String.downcase(content_type), "image/svg")

  defp header_value(headers, name) do
    Enum.find_value(headers, fn {key, value} ->
      if String.downcase(key) == name, do: value
    end)
  end

  defp send_favicon(response, conn) do
    conn =
      conn
      |> put_resp_header("content-type", response.content_type)
      |> put_resp_header("cache-control", @browser_cache_control)

    conn = if response.secure?, do: prevent_javascript_execution(conn), else: conn

    conn
    |> send_resp(200, response.body)
    |> halt()
  end

  defp prevent_javascript_execution(conn) do
    conn
    |> put_resp_header("content-security-policy", "script-src 'none'")
    |> put_resp_header("content-disposition", "attachment")
  end
end
