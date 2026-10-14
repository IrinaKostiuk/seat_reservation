defmodule SeatReservationWeb.Layouts do
  use SeatReservationWeb, :html

  def root(assigns) do
    ~H"""
    <!DOCTYPE html>
    <html lang="uk" class="h-full bg-slate-950 text-slate-100">
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <meta name="csrf-token" content={get_csrf_token()} />
        <title>Бронювання місць на концерт</title>
        <script src="https://cdn.tailwindcss.com"></script>
        <script src="https://cdn.jsdelivr.net/npm/phoenix@1.7.14/priv/static/phoenix.min.js"></script>
        <script src="https://cdn.jsdelivr.net/npm/phoenix_live_view@0.20.17/priv/static/phoenix_live_view.min.js"></script>
        <script>
          document.addEventListener("DOMContentLoaded", () => {
            let csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
            let liveSocket = new LiveView.LiveSocket("/live", Phoenix.Socket, {params: {_csrf_token: csrfToken}})
            liveSocket.connect()
            window.liveSocket = liveSocket
          })
        </script>
      </head>
      <body class="min-h-full flex flex-col antialiased selection:bg-indigo-500 selection:text-white">
        <%= @inner_content %>
      </body>
    </html>
    """
  end

  def app(assigns) do
    ~H"""
    <main class="flex-1">
      <%= @inner_content %>
    </main>
    """
  end
end
