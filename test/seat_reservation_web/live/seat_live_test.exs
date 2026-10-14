defmodule SeatReservationWeb.SeatLiveTest do
  use ExUnit.Case, async: false
  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  @endpoint SeatReservationWeb.Endpoint

  setup do
    for {seat, state} <- SeatReservation.seats() do
      case state do
        {:held, fan} -> SeatReservation.release(seat, fan)
        {:confirmed, fan} -> SeatReservation.release(seat, fan)
        :free -> :ok
      end
    end

    :ok
  end

  test "renders concert hall and handles seat hold and release" do
    conn = build_conn()
    {:ok, view, html} = live(conn, "/")

    assert html =~ "Сервер бронювання квитків на концерт"
    assert html =~ "Схема залу"

    # Select and hold seat 10
    assert render_click(view, "select_seat", %{"seat" => "10"}) =~ "#10"
    assert render_click(view, "hold", %{"seat" => "10"}) =~ "Місце #10 утримано"

    # Confirm seat 10
    assert render_click(view, "confirm", %{"seat" => "10"}) =~ "Місце #10 успішно підтверджено"

    # Release seat 10
    assert render_click(view, "release", %{"seat" => "10"}) =~ "Місце #10 звільнено"
  end
end
