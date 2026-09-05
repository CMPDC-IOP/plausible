defmodule PlausibleWeb.SitePath do
  @moduledoc """
  Represents a site domain as one URL path segment, even behind proxies that
  normalize percent-encoded slashes. Site validation reserves `~`, so it can
  stand for `/` without changing the stored domain or query/body parameters.
  """

  def encode(domain), do: String.replace(domain, "/", "~")

  def decode(domain), do: String.replace(domain, "~", "/")

  def encode_segment(domain) do
    domain |> encode() |> URI.encode_www_form()
  end
end
