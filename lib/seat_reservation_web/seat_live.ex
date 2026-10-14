defmodule SeatReservationWeb.SeatLive do
  use Phoenix.LiveView

  alias SeatReservation, as: Seats

  @impl true
  def mount(_params, session, socket) do
    fan =
      if connected?(socket) do
        fan = SeatReservation.BrowserSession.connect(session["browser_id"])
        :ok = Seats.subscribe()
        fan
      end

    {:ok, socket |> assign(fan: fan, notice: nil) |> refresh()}
  end

  @impl true
  def handle_event(action, %{"seat" => value}, socket)
      when action in ["hold", "confirm", "release"] and is_binary(value) do
    result =
      with fan when is_pid(fan) <- socket.assigns.fan,
           {seat, ""} when seat in 1..100 <- Integer.parse(value) do
        SeatReservation.BrowserSession.action(fan, action, seat)
      else
        _ -> {:error, :invalid}
      end

    notice =
      case {action, result} do
        {"hold", :ok} ->
          "Seat held. Confirm within 10 seconds to make it yours."

        {"confirm", :ok} ->
          "You're in. Your seat is confirmed!"

        {"release", :ok} ->
          "Seat released. There's always another spot."

        {_, {:error, :taken}} ->
          "Someone just got that seat. Try another available spot."

        {_, {:error, :not_held}} ->
          "That hold has expired. Choose an available seat to try again."

        _ ->
          "That seat isn't available. Please choose a seat on the map."
      end

    {:noreply, socket |> assign(notice: notice) |> refresh()}
  end

  def handle_event(_event, _params, socket), do: {:noreply, socket}

  @impl true
  def handle_info({:seat_event, seat, kind, fan}, socket) do
    socket =
      if kind == :released and fan == socket.assigns.fan and
           socket.assigns.seats[seat] == {:held, fan} do
        assign(socket, notice: "Your hold expired. Choose an available seat to try again.")
      else
        socket
      end

    {:noreply, refresh(socket)}
  end

  defp refresh(socket) do
    seats = Seats.seats()
    fan = socket.assigns.fan

    owned =
      seats
      |> Enum.filter(fn
        {_seat, {_kind, owner}} -> owner == fan
        _ -> false
      end)
      |> Enum.sort()

    assign(socket,
      seats: seats,
      owned: owned,
      available: Enum.count(seats, fn {_, state} -> state == :free end)
    )
  end

  defp seat_label(seat), do: "#{List.to_string([?A + div(seat - 1, 10)])}#{rem(seat - 1, 10) + 1}"
  defp seat_class(:free, _fan), do: "available"
  defp seat_class({:held, owner}, fan) when owner == fan, do: "mine"
  defp seat_class({:confirmed, owner}, fan) when owner == fan, do: "confirmed-mine"
  defp seat_class({:held, _}, _fan), do: "held"
  defp seat_class({:confirmed, _}, _fan), do: "confirmed"

  defp seat_description(:free, _fan), do: "available — hold this seat"
  defp seat_description({:held, owner}, fan) when owner == fan, do: "held by you"
  defp seat_description({:confirmed, owner}, fan) when owner == fan, do: "confirmed for you"
  defp seat_description({:held, _}, _fan), do: "held by another guest"
  defp seat_description({:confirmed, _}, _fan), do: "reserved"

  @impl true
  def render(assigns) do
    ~H"""
    <div class="app-shell">
      <header class="site-header">
        <a class="wordmark" href="/" aria-label="Encore home">encore<span>✳</span></a>
        <span class="header-note">GOOD MUSIC. GREAT COMPANY.</span>
        <div class="live-indicator"><span></span> <span class="online-label">Live availability</span><span class="offline-label">Reconnecting…</span></div>
      </header>

      <main>
        <section class="intro" aria-labelledby="page-title">
          <div>
            <p class="eyebrow"><span class="short-rule"></span> ONE NIGHT. ONE HUNDRED SEATS.</p>
            <h1 id="page-title">Find your place.<br /><em>Feel the music.</em></h1>
            <p class="intro-copy">A little closer to the stage. A little further from the everyday.<br class="desktop-break" /> Your next great night starts with a seat.</p>
          </div>
          <div class="event-mark" aria-hidden="true">
            <div class="record"><div class="record-label">e<span>LIVE<br />SESSIONS</span></div></div>
            <span class="record-caption">THE ENCORE SESSIONS · LIVE IN CONCERT</span>
          </div>
        </section>

        <div class="booking-layout">
          <section class="seat-map card" aria-labelledby="map-title">
            <div class="card-heading">
              <div><p class="eyebrow">THE MAIN ROOM</p><h2 id="map-title">Choose your seat</h2></div>
              <span id="availability" class="availability"><strong><%= @available %></strong> available</span>
            </div>
            <div class="legend" aria-label="Seat legend">
              <span><i class="swatch available"></i> Available</span>
              <span><i class="swatch mine"></i> Your hold</span>
              <span><i class="swatch held"></i> On hold</span>
              <span><i class="swatch confirmed"></i> Reserved</span>
            </div>
            <div class="stage"><span>STAGE</span><p>You're facing the music</p></div>
            <div class="seating" aria-label="100 seats in rows A to J">
              <div :for={row <- 0..9} class="seat-row">
                <span class="row-label" aria-hidden="true"><%= List.to_string([?A + row]) %></span>
                <button
                  :for={column <- 1..10}
                  id={"seat-#{row * 10 + column}"}
                  class={["seat", seat_class(@seats[row * 10 + column], @fan), column == 6 && "after-aisle"]}
                  phx-click="hold"
                  phx-value-seat={row * 10 + column}
                  disabled={@seats[row * 10 + column] != :free or is_nil(@fan)}
                  aria-label={"Seat #{seat_label(row * 10 + column)}, #{seat_description(@seats[row * 10 + column], @fan)}"}
                  title={"#{seat_label(row * 10 + column)} · #{seat_description(@seats[row * 10 + column], @fan)}"}
                ><%= column %></button>
                <span class="row-label end-label" aria-hidden="true"><%= List.to_string([?A + row]) %></span>
              </div>
            </div>
            <div class="map-footer"><span>100 seats · Every spot has a story</span><span>EXIT ↗</span></div>
          </section>

          <aside class="reservation-column" aria-labelledby="your-seats-title">
            <section class="reservation card">
              <div class="card-heading"><div><p class="eyebrow">MAKE IT A NIGHT</p><h2 id="your-seats-title">Your seats</h2></div><span class="seat-count"><%= length(@owned) %></span></div>
              <p id="notice" class="notice" role="status" aria-live="polite"><%= @notice %></p>
              <div :if={@owned == []} id="empty-reservation" class="empty-state">
                <svg viewBox="0 0 80 64" fill="none" aria-hidden="true"><path d="M22 35V15a7 7 0 0 1 7-7h22a7 7 0 0 1 7 7v20M16 29v17a5 5 0 0 0 5 5h38a5 5 0 0 0 5-5V29M22 39h36M24 51v8M56 51v8" stroke="currentColor" stroke-width="3" stroke-linecap="round"/><path d="M34 20h12" stroke="currentColor" stroke-width="3" stroke-linecap="round"/></svg>
                <h3>A spot with your name on it.</h3>
                <p>Pick an available seat on the map.<br />We'll save it for you for 10 seconds.</p>
              </div>
              <ul :if={@owned != []} id="your-seats" class="ticket-list">
                <li :for={{seat, {kind, _}} <- @owned} id={"reservation-#{seat}"} class="ticket">
                  <div class="ticket-top"><strong class="ticket-seat"><%= seat_label(seat) %></strong><span class={["status-pill", kind == :confirmed && "is-confirmed"]}><%= if kind == :held, do: "On hold", else: "Confirmed" %></span></div>
                  <p><%= if kind == :held, do: "Confirm within 10 seconds of holding.", else: "This spot is yours. See you at the show." %></p>
                  <div class="ticket-actions">
                    <button :if={kind == :held} id={"confirm-#{seat}"} class="primary-button" phx-click="confirm" phx-value-seat={seat}>Confirm seat <span>↗</span></button>
                    <button id={"release-#{seat}"} class="text-button" phx-click="release" phx-value-seat={seat}><%= if kind == :held, do: "Let it go", else: "Release seat" %></button>
                  </div>
                </li>
              </ul>
              <div class="reservation-note"><span aria-hidden="true">◷</span><p>Take a seat, then make it yours.<br /><strong>Unconfirmed holds expire after 10 seconds.</strong></p></div>
            </section>
            <section class="how-it-works" aria-labelledby="how-title">
              <p id="how-title" class="eyebrow">THREE STEPS TO THE FRONT ROW</p>
              <ol><li><span>01</span><div><strong>Find your spot</strong><p>Choose any available seat.</p></div></li><li><span>02</span><div><strong>Make it yours</strong><p>Confirm before your hold expires.</p></div></li><li><span>03</span><div><strong>Enjoy the night</strong><p>Your confirmed seat stays reserved.</p></div></li></ol>
            </section>
          </aside>
        </div>
        <p class="connection-notice" role="alert">Connecting to live availability. Seat controls will return when you're connected.</p>
        <noscript><p class="notice">Enable JavaScript to reserve seats and see live availability.</p></noscript>
      </main>
      <footer class="site-footer"><span class="footer-brand">encore✳</span><span>Less scrolling. More live music.</span><span>100 seats. One shared experience.</span></footer>
    </div>
    """
  end
end
