defmodule SeatReservationWeb.SeatsLive do
  @moduledoc """
  The seat map page.

  Each browser tab runs one LiveView process, and that process is the fan: it
  holds, confirms and releases seats as itself through the public
  `SeatReservation` API, and it is subscribed to every seat event. Closing the
  tab ends the process, which frees its unconfirmed holds.

  The seat map changes only through seat events, including for this tab's own
  actions. The server sends the event before it replies, so the event is
  already waiting in the mailbox when a call returns.
  """
  use Phoenix.LiveView

  import SeatReservation, only: [is_seat: 1]

  @notice_ms 4_000
  @unavailable "Couldn't reach the server. Try again."

  @impl true
  def mount(_params, _session, socket) do
    # Subscribe before taking the snapshot, so the events that follow always
    # apply on top of it.
    if connected?(socket), do: :ok = SeatReservation.subscribe()

    {:ok,
     assign(socket,
       me: self(),
       seats: SeatReservation.seats(),
       deadlines: %{},
       notice: nil,
       hold_ms: SeatReservation.hold_timeout_ms()
     )}
  end

  @impl true
  def handle_event("toggle", %{"seat" => seat}, socket) do
    {:noreply, with_seat(socket, seat, &toggle/2)}
  end

  def handle_event("release", %{"seat" => seat}, socket) do
    {:noreply, with_seat(socket, seat, &release/2)}
  end

  def handle_event("confirm", _params, socket) do
    %{me: me, seats: seats} = socket.assigns

    results =
      for {seat, {:held, ^me}} <- seats,
          do: {seat, call(fn -> SeatReservation.confirm(seat, me) end)}

    confirmed = for {seat, {:ok, :ok}} <- results, do: seat
    # A hold that expired just before confirming is reported by its own event.
    socket = update(socket, :deadlines, &Map.drop(&1, confirmed))

    if Enum.any?(results, &match?({_seat, :unavailable}, &1)),
      do: {:noreply, notify(socket, @unavailable)},
      else: {:noreply, socket}
  end

  # Events come from the browser and cannot be trusted; anything else is ignored.
  def handle_event(_event, _params, socket), do: {:noreply, socket}

  @impl true
  def handle_info({:seat_event, seat, kind, fan}, socket) do
    socket = update(socket, :seats, &Map.put(&1, seat, seat_state(kind, fan)))
    {:noreply, note_expiry(socket, seat, kind, fan)}
  end

  def handle_info({:clear_notice, id}, %{assigns: %{notice: %{id: id}}} = socket) do
    {:noreply, assign(socket, notice: nil)}
  end

  def handle_info(_message, socket), do: {:noreply, socket}

  ## Actions

  defp toggle(socket, seat) do
    case seat_kind(socket.assigns.seats[seat], socket.assigns.me) do
      :free -> hold(socket, seat)
      :holding -> release(socket, seat)
      _unavailable -> socket
    end
  end

  defp hold(socket, seat) do
    case call(fn -> SeatReservation.hold(seat, socket.assigns.me) end) do
      {:ok, :ok} ->
        deadline = now() + socket.assigns.hold_ms
        update(socket, :deadlines, &Map.put(&1, seat, deadline))

      {:ok, {:error, _taken}} ->
        notify(socket, "Seat #{seat} was just taken")

      :unavailable ->
        notify(socket, @unavailable)
    end
  end

  defp release(socket, seat) do
    case call(fn -> SeatReservation.release(seat, socket.assigns.me) end) do
      {:ok, :ok} -> update(socket, :deadlines, &Map.delete(&1, seat))
      :unavailable -> notify(socket, @unavailable)
    end
  end

  # A :released event for a seat this tab still tracks means the hold ran out:
  # the tab forgets a seat as soon as it releases or confirms it itself.
  defp note_expiry(%{assigns: %{me: me, deadlines: deadlines}} = socket, seat, :released, me)
       when is_map_key(deadlines, seat) do
    socket
    |> assign(deadlines: Map.delete(deadlines, seat))
    |> notify("Your hold on seat #{seat} expired")
  end

  defp note_expiry(socket, _seat, _kind, _fan), do: socket

  defp notify(socket, text) do
    id = make_ref()
    Process.send_after(self(), {:clear_notice, id}, @notice_ms)
    assign(socket, notice: %{id: id, text: text})
  end

  # The seat server is briefly unreachable while it restarts after a crash.
  # Failing the call then shows a notice instead of crashing this tab, which
  # would release its holds.
  defp call(fun) do
    {:ok, fun.()}
  catch
    :exit, _reason -> :unavailable
  end

  defp with_seat(socket, raw, fun) do
    case parse_seat(raw) do
      {:ok, seat} -> fun.(socket, seat)
      :error -> socket
    end
  end

  defp parse_seat(raw) when is_binary(raw) do
    case Integer.parse(raw) do
      {seat, ""} when is_seat(seat) -> {:ok, seat}
      _invalid -> :error
    end
  end

  defp parse_seat(_raw), do: :error

  ## Rendering

  @impl true
  def render(assigns) do
    ~H"""
    <main class="page">
      <header class="header">
        <div>
          <h1 class="title">Reserve your seat</h1>
          <p class="subtitle">Holds expire after {seconds(@hold_ms)} seconds unless confirmed</p>
        </div>
        <p class="status">
          <span class="status-dot" aria-hidden="true"></span>
          <span class="status-text">
            <span class="when-online">{available(@seats)} available</span>
            <span class="when-offline">Connecting…</span>
          </span>
        </p>
      </header>

      <div class="layout">
        <section class="map" aria-label="Seat map">
          <div class="stage" aria-hidden="true">Stage</div>
          <div class="seats">
            <.seat
              :for={{seat, state} <- Enum.sort(@seats)}
              :key={seat}
              seat={seat}
              kind={seat_kind(state, @me)}
            />
          </div>
          <ul class="legend" aria-hidden="true">
            <li><span class="swatch swatch-free"></span>Available</li>
            <li><span class="swatch swatch-held"></span>On hold</li>
            <li><span class="swatch swatch-sold"></span>Sold</li>
            <li><span class="swatch swatch-owned"></span>Yours</li>
          </ul>
        </section>

        <aside class="panel" aria-labelledby="panel-title">
          <.panel
            holds={holds(@seats, @me, @deadlines, @hold_ms)}
            owned={owned(@seats, @me)}
            hold_ms={@hold_ms}
          />
          <p class="notice" role="status"><span :if={@notice}>{@notice.text}</span></p>
        </aside>
      </div>
    </main>
    """
  end

  attr :seat, :integer, required: true
  attr :kind, :atom, values: [:free, :holding, :held, :sold, :owned], required: true

  defp seat(assigns) do
    ~H"""
    <button
      type="button"
      class={["seat", "seat-#{@kind}"]}
      phx-click="toggle"
      phx-value-seat={@seat}
      disabled={@kind in [:held, :sold, :owned]}
      aria-label={"Seat #{@seat}, #{seat_label(@kind)}"}
    >
      {@seat}
    </button>
    """
  end

  attr :holds, :list, required: true, doc: "`{seat, remaining_ms}` for each seat this tab holds"
  attr :owned, :list, required: true, doc: "seats this tab has confirmed"
  attr :hold_ms, :integer, required: true

  defp panel(assigns) do
    ~H"""
    <h2 id="panel-title" class="panel-title">Your seats</h2>

    <p :if={@holds == [] and @owned == []} class="hint">
      Pick a seat to hold it for {seconds(@hold_ms)} seconds.
    </p>

    <ul :if={@holds != []} class="rows">
      <li
        :for={{seat, remaining} <- @holds}
        :key={seat}
        id={"hold-#{seat}"}
        class="row row-hold"
        phx-hook="Countdown"
        data-remaining={remaining}
        data-total={@hold_ms}
      >
        <span>Seat {seat}</span>
        <span class="row-meta" data-seconds>{seconds(remaining)}s</span>
        <button
          type="button"
          class="icon-button"
          phx-click="release"
          phx-value-seat={seat}
          aria-label={"Release seat #{seat}"}
        >
          <svg viewBox="0 0 16 16" width="16" height="16" aria-hidden="true">
            <path
              d="M4.5 4.5l7 7m0-7l-7 7"
              stroke="currentColor"
              stroke-width="1.5"
              stroke-linecap="round"
            />
          </svg>
        </button>
        <span class="countdown" aria-hidden="true"><span class="countdown-fill" data-fill></span></span>
      </li>
    </ul>

    <button :if={@holds != []} type="button" class="button-primary" phx-click="confirm">
      Confirm {length(@holds)} {if length(@holds) == 1, do: "seat", else: "seats"}
    </button>

    <ul :if={@owned != []} class="rows">
      <li :for={seat <- @owned} :key={seat} class="row">
        <span>Seat {seat}</span>
        <span class="row-meta row-meta-success">Confirmed</span>
        <button
          type="button"
          class="text-button"
          phx-click="release"
          phx-value-seat={seat}
          data-confirm={"Release seat #{seat}? Anyone can take it after that."}
        >
          Release
        </button>
      </li>
    </ul>
    """
  end

  ## View helpers

  defp seat_state(:held, fan), do: {:held, fan}
  defp seat_state(:confirmed, fan), do: {:confirmed, fan}
  defp seat_state(:released, _fan), do: :free

  defp seat_kind(:free, _me), do: :free
  defp seat_kind({:held, me}, me), do: :holding
  defp seat_kind({:confirmed, me}, me), do: :owned
  defp seat_kind({:held, _fan}, _me), do: :held
  defp seat_kind({:confirmed, _fan}, _me), do: :sold

  defp seat_label(:free), do: "available"
  defp seat_label(:holding), do: "held by you"
  defp seat_label(:held), do: "on hold"
  defp seat_label(:sold), do: "sold"
  defp seat_label(:owned), do: "yours"

  defp available(seats), do: Enum.count(seats, &match?({_seat, :free}, &1))

  defp holds(seats, me, deadlines, hold_ms) do
    now = now()

    for {seat, {:held, ^me}} <- Enum.sort(seats) do
      {seat, max(Map.get(deadlines, seat, now + hold_ms) - now, 0)}
    end
  end

  defp owned(seats, me), do: for({seat, {:confirmed, ^me}} <- Enum.sort(seats), do: seat)

  defp seconds(ms), do: div(ms + 999, 1_000)

  defp now, do: System.monotonic_time(:millisecond)
end
