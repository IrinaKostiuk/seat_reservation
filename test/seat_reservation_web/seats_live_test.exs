defmodule SeatReservationWeb.SeatsLiveTest do
  # Uses the application's seat server, which other test modules share.
  use ExUnit.Case, async: false

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  @endpoint SeatReservationWeb.Endpoint

  setup do
    %{conn: build_conn()}
  end

  test "renders all 100 seats with their state", %{conn: conn} do
    {:ok, view, html} = live(conn, "/")

    assert html =~ "Reserve your seat"
    assert view |> element(".seats") |> render() |> count_seats() == 100
  end

  test "clicking a free seat holds it for this tab", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/")
    seat = free_seat()

    click_seat(view, seat)

    assert SeatReservation.seats()[seat] == {:held, view.pid}
    assert has_element?(view, ~s([aria-label="Seat #{seat}, held by you"]))
    assert has_element?(view, "#hold-#{seat}")
    assert has_element?(view, "button", "Confirm 1 seat")
  end

  test "clicking your held seat releases it", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/")
    seat = free_seat()

    click_seat(view, seat)
    click_seat(view, seat)

    assert SeatReservation.seats()[seat] == :free
    refute has_element?(view, "#hold-#{seat}")
  end

  test "confirming turns held seats into tickets", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/")
    seat = free_seat()

    click_seat(view, seat)
    view |> element("button", "Confirm 1 seat") |> render_click()

    assert SeatReservation.seats()[seat] == {:confirmed, view.pid}
    assert has_element?(view, ~s([aria-label="Seat #{seat}, yours"]))

    view |> element(~s(button[phx-value-seat="#{seat}"]), "Release") |> render_click()
    assert SeatReservation.seats()[seat] == :free
  end

  test "other tabs see changes live", %{conn: conn} do
    {:ok, alice, _html} = live(conn, "/")
    {:ok, bob, _html} = live(build_conn(), "/")
    seat = free_seat()

    click_seat(alice, seat)

    assert has_element?(bob, ~s([aria-label="Seat #{seat}, on hold"][disabled]))
  end

  test "closing a tab frees the seats it held", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/")
    :ok = SeatReservation.subscribe()
    seat = free_seat()
    click_seat(view, seat)
    tab = view.pid

    Process.exit(tab, :kill)

    assert_receive {:seat_event, ^seat, :released, ^tab}
    assert SeatReservation.seats()[seat] == :free
  end

  test "shows when a seat was taken first or a hold expired", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/")
    seat = free_seat()

    # Another fan takes the seat; this tab hasn't processed the event yet.
    :sys.suspend(view.pid)
    :ok = SeatReservation.hold(seat, self())
    :sys.resume(view.pid)
    send(view.pid, {:seat_event, seat, :released, self()})
    click_seat(view, seat)
    assert render(view) =~ "Seat #{seat} was just taken"
    :ok = SeatReservation.release(seat, self())

    # The server reports the expiry of this tab's own hold.
    click_seat(view, seat)
    send(view.pid, {:seat_event, seat, :released, view.pid})
    assert render(view) =~ "Your hold on seat #{seat} expired"
  end

  test "malformed events from the browser are ignored", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/")

    for value <- ["0", "101", "abc", "1.5", ""] do
      render_hook(view, "toggle", %{"seat" => value})
      render_hook(view, "release", %{"seat" => value})
    end

    render_hook(view, "toggle", %{"seat" => ["1"]})
    render_hook(view, "toggle", %{})
    render_hook(view, "unknown", %{})

    assert Process.alive?(view.pid)
    assert render(view) =~ "Reserve your seat"
  end

  defp click_seat(view, seat) do
    view |> element(~s(.seat[phx-value-seat="#{seat}"])) |> render_click()
    # Seat events arrive as messages; rendering again processes them.
    render(view)
  end

  defp count_seats(html), do: html |> String.split(~s(class="seat )) |> length() |> Kernel.-(1)

  defp free_seat do
    Enum.find_value(SeatReservation.seats(), fn {seat, state} -> state == :free && seat end)
  end
end
