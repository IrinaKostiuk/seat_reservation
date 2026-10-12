defmodule SeatReservationWeb.BrowserIdentity do
  @moduledoc false
  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    if get_session(conn, "browser_id") do
      conn
    else
      put_session(conn, "browser_id", Base.url_encode64(:crypto.strong_rand_bytes(24)))
    end
  end
end
