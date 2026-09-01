defmodule PlausibleWeb.URL do
  @moduledoc false

  alias PlausibleWeb.Endpoint

  def base_url do
    Endpoint.config(:url)
    |> base_url()
  end

  @doc false
  def base_url(url_config) do
    %URI{
      scheme: to_string(Keyword.get(url_config, :scheme, "http")),
      host: Keyword.fetch!(url_config, :host),
      port: Keyword.get(url_config, :port),
      path: base_path(url_config)
    }
    |> URI.to_string()
    |> String.trim_trailing("/")
  end

  def path(path) do
    Endpoint.config(:url)
    |> path(path)
  end

  @doc false
  def path(url_config, path) do
    base_path(url_config) <> "/" <> String.trim_leading(path, "/")
  end

  def url(path) do
    Endpoint.config(:url)
    |> url(path)
  end

  @doc false
  def url(url_config, path) do
    base_url(url_config) <> "/" <> String.trim_leading(path, "/")
  end

  defp base_path(url_config) do
    case Keyword.get(url_config, :path) do
      path when path in [nil, "/"] -> ""
      path -> "/" <> (path |> String.trim_leading("/") |> String.trim_trailing("/"))
    end
  end
end
