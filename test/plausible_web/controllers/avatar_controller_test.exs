defmodule PlausibleWeb.AvatarControllerTest do
  use PlausibleWeb.ConnCase, async: true

  setup {PlausibleWeb.FirstLaunchPlug.Test, :skip}

  describe "GET /avatar/:hash" do
    test "returns a deterministic local avatar", %{conn: conn} do
      conn = get(conn, "/avatar/myhash")

      assert response(conn, 200) =~ "<svg"
      assert get_resp_header(conn, "content-type") == ["image/svg+xml; charset=utf-8"]
      assert get_resp_header(conn, "cache-control") == ["public, max-age=2592000"]

      other_conn = get(recycle(conn), "/avatar/another-hash")

      refute response(other_conn, 200) == response(conn, 200)
    end
  end
end
