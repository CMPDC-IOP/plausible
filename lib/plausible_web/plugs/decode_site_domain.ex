defmodule PlausibleWeb.Plugs.DecodeSiteDomain do
  @moduledoc false
  @behaviour Plug

  def init(opts), do: opts

  def call(conn, _opts) do
    Enum.reduce(["domain", "site_id"], conn, fn param, conn ->
      case conn.path_params do
        %{^param => domain} when is_binary(domain) ->
          domain = PlausibleWeb.SitePath.decode(domain)

          %{
            conn
            | path_params: Map.put(conn.path_params, param, domain),
              params: Map.put(conn.params, param, domain)
          }

        _ ->
          conn
      end
    end)
  end
end
