defmodule SeatReservationWeb.SeatLiveTest do
  use ExUnit.Case, async: false
  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  @endpoint SeatReservationWeb.Endpoint

  setup do
    for {_, pid, _, _} <- DynamicSupervisor.which_children(SeatReservation.BrowserSessions) do
      DynamicSupervisor.terminate_child(SeatReservation.BrowserSessions, pid)
    end

    :ok = Supervisor.terminate_child(SeatReservation.Supervisor, SeatReservation.Server)
    {:ok, _} = Supervisor.restart_child(SeatReservation.Supervisor, SeatReservation.Server)
    :ok
  end

  test "page renders all seats, local assets, and accessible instructions" do
    conn = get(build_conn(), "/")
    html = html_response(conn, 200)
    assert html =~ "Choose your seat"
    assert html =~ "csrf-token"
    assert html =~ "Enable JavaScript"
    assert length(Floki.find(html, "button.seat")) == 100

    assert Enum.all?(Floki.find(html, "button.seat"), fn {_, attrs, _} ->
             List.keymember?(attrs, "aria-label", 0)
           end)

    for path <- [
          "/assets/app.js",
          "/assets/app.css",
          "/vendor/phoenix/phoenix.mjs",
          "/vendor/live-view/phoenix_live_view.esm.js"
        ] do
      assert get(build_conn(), path).status == 200
    end
  end

  test "a guest can hold, confirm, refresh, and release a seat" do
    conn = browser_conn("guest-one")
    {:ok, view, _} = live(conn, "/")
    assert has_element?(view, "#empty-reservation")
    view |> element("#seat-1") |> render_click()
    assert has_element?(view, "#reservation-1", "On hold")
    view |> element("#confirm-1") |> render_click()
    assert has_element?(view, "#reservation-1", "Confirmed")
    {:confirmed, owner} = SeatReservation.seats()[1]
    GenServer.stop(view.pid)

    {:ok, refreshed, _} = live(conn, "/")
    assert has_element?(refreshed, "#reservation-1", "Confirmed")
    assert SeatReservation.seats()[1] == {:confirmed, owner}
    refreshed |> element("#release-1") |> render_click()
    assert SeatReservation.seats()[1] == :free
    assert has_element?(refreshed, "#empty-reservation")
  end

  test "different browsers see live updates and cannot change each other's seats" do
    {:ok, first, _} = live(browser_conn("first"), "/")
    {:ok, second, _} = live(browser_conn("second"), "/")
    first |> element("#seat-1") |> render_click()
    assert has_element?(second, "#seat-1.held[disabled]")
    assert has_element?(second, "#availability", "99")

    assert render_click(second, "hold", %{"seat" => "1"}) =~ "Someone just got that seat"
    assert render_click(second, "confirm", %{"seat" => "1"}) =~ "That hold has expired"
    render_click(second, "release", %{"seat" => "1"})
    assert {:held, _} = SeatReservation.seats()[1]
    first |> element("#confirm-1") |> render_click()
    assert has_element?(second, "#seat-1.confirmed[disabled]")
    first |> element("#release-1") |> render_click()
    assert has_element?(second, "#seat-1.available:not([disabled])")
  end

  test "last tab disconnect releases holds while a sibling tab preserves them" do
    conn = browser_conn("shared-browser")
    {:ok, first, _} = live(conn, "/")
    {:ok, second, _} = live(conn, "/")
    first |> element("#seat-1") |> render_click()
    assert has_element?(second, "#reservation-1", "On hold")
    GenServer.stop(first.pid)
    assert {:held, _} = SeatReservation.seats()[1]
    GenServer.stop(second.pid)
    eventually(fn -> SeatReservation.seats()[1] == :free end)
  end

  test "expiry updates the map and removes the hold controls" do
    {:ok, view, _} = live(browser_conn("expiry"), "/")
    view |> element("#seat-1") |> render_click()

    :sys.replace_state(SeatReservation.Server, fn state ->
      put_in(state, [:holds, 1, :deadline], System.monotonic_time(:millisecond) - 1)
    end)

    assert SeatReservation.seats()[1] == :free
    assert has_element?(view, "#seat-1.available:not([disabled])")
    refute has_element?(view, "#confirm-1")
    assert has_element?(view, "#notice", "Your hold expired")
  end

  test "malformed events do not crash the view or modify seats" do
    {:ok, view, _} = live(browser_conn("invalid"), "/")

    for seat <- ["0", "101", "banana", "1junk", 1, nil, %{}] do
      render_click(view, "hold", %{"seat" => seat})
    end

    render_click(view, "hold", %{})
    render_click(view, "unknown", %{})
    assert Process.alive?(view.pid)
    assert Enum.all?(SeatReservation.seats(), fn {_, value} -> value == :free end)
  end

  defp browser_conn(id), do: build_conn() |> Plug.Test.init_test_session(%{"browser_id" => id})

  defp eventually(check, attempts \\ 100)
  defp eventually(check, 0), do: assert(check.())

  defp eventually(check, attempts) do
    unless check.() do
      Process.sleep(10)
      eventually(check, attempts - 1)
    end
  end
end
