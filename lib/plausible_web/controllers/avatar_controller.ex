defmodule PlausibleWeb.AvatarController do
  @moduledoc """
  Generates deterministic local avatars without disclosing user information to third parties.
  """
  use PlausibleWeb, :controller

  def avatar(conn, %{"hash" => hash}) do
    <<red, green, blue, _rest::binary>> = :crypto.hash(:sha256, hash)
    color = Base.encode16(<<red, green, blue>>, case: :lower)

    body = """
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 150 150">
      <rect width="150" height="150" rx="75" fill="##{color}"/>
      <circle cx="75" cy="56" r="28" fill="#fff" opacity=".9"/>
      <path d="M25 137c4-29 24-45 50-45s46 16 50 45" fill="#fff" opacity=".9"/>
    </svg>
    """

    conn
    |> put_resp_content_type("image/svg+xml")
    |> put_resp_header("cache-control", "public, max-age=2592000")
    |> put_resp_header("content-security-policy", "default-src 'none'")
    |> put_resp_header("x-content-type-options", "nosniff")
    |> send_resp(200, body)
  end
end
