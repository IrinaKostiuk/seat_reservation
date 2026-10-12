defmodule SeatReservationWeb.Layout do
  use Phoenix.Component

  def root(assigns) do
    ~H"""
    <!DOCTYPE html>
    <html lang="en">
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <meta name="csrf-token" content={Plug.CSRFProtection.get_csrf_token()} />
        <meta name="description" content="Find your seat for an intimate night of live music. Reserve, confirm, and watch availability update live." />
        <title>Encore — Find your seat</title>
        <link rel="icon" href="data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 64 64'%3E%3Crect width='64' height='64' rx='16' fill='%23d34a2f'/%3E%3Ctext x='17' y='46' fill='white' font-size='44' font-family='Georgia'%3Ee%3C/text%3E%3C/svg%3E" />
        <link rel="stylesheet" href="/assets/app.css" />
        <script type="module" src="/assets/app.js"></script>
      </head>
      <body><%= @inner_content %></body>
    </html>
    """
  end
end

defmodule SeatReservationWeb.ErrorHTML do
  def render(template, _assigns), do: Phoenix.Controller.status_message_from_template(template)
end
