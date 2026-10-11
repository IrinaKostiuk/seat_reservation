defmodule SeatReservationWeb.ErrorHTML do
  @moduledoc "Renders error pages as their plain status message, e.g. \"Not Found\"."

  def render(template, _assigns), do: Phoenix.Controller.status_message_from_template(template)
end
