defmodule SeatReservationWeb.Router do
  use Phoenix.Router

  import Phoenix.Controller
  import Phoenix.LiveView.Router
  import Plug.Conn

  # Everything the page loads comes from this origin; there are no inline
  # scripts or styles.
  @content_security_policy Enum.join(
                             [
                               "default-src 'self'",
                               "connect-src 'self'",
                               "img-src 'self' data:",
                               "base-uri 'self'",
                               "form-action 'self'",
                               "frame-ancestors 'none'"
                             ],
                             "; "
                           )

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :put_root_layout, html: {SeatReservationWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers, %{"content-security-policy" => @content_security_policy}
  end

  scope "/", SeatReservationWeb do
    pipe_through :browser

    live "/", SeatsLive
  end
end
