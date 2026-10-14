defmodule SeatReservationWeb.SeatLive do
  use SeatReservationWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      SeatReservation.subscribe()
    end

    seats = SeatReservation.seats()

    {:ok,
     assign(socket,
       seats: seats,
       my_pid: self(),
       events_log: [],
       selected_seat: nil
     )}
  end

  @impl true
  def handle_event("select_seat", %{"seat" => seat_str}, socket) do
    seat = String.to_integer(seat_str)
    {:noreply, assign(socket, selected_seat: seat)}
  end

  def handle_event("hold", %{"seat" => seat_str}, socket) do
    seat = String.to_integer(seat_str)

    case SeatReservation.hold(seat, self()) do
      :ok ->
        seats = Map.put(socket.assigns.seats, seat, {:held, self()})

        {:noreply,
         socket
         |> assign(seats: seats, selected_seat: seat)
         |> put_flash(:info, "Місце ##{seat} утримано! Підтвердіть протягом 10 секунд.")}

      {:error, :taken} ->
        {:noreply, put_flash(socket, :error, "Місце ##{seat} вже зайняте іншим фанатом.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Не вдалося утримати місце ##{seat}.")}
    end
  end

  def handle_event("confirm", %{"seat" => seat_str}, socket) do
    seat = String.to_integer(seat_str)

    case SeatReservation.confirm(seat, self()) do
      :ok ->
        seats = Map.put(socket.assigns.seats, seat, {:confirmed, self()})

        {:noreply,
         socket
         |> assign(seats: seats)
         |> put_flash(:info, "Місце ##{seat} успішно підтверджено та оплачено!")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Помилка підтвердження місця ##{seat}.")}
    end
  end

  def handle_event("release", %{"seat" => seat_str}, socket) do
    seat = String.to_integer(seat_str)
    SeatReservation.release(seat, self())
    seats = Map.put(socket.assigns.seats, seat, :free)
    {:noreply, socket |> assign(seats: seats) |> put_flash(:info, "Місце ##{seat} звільнено.")}
  end

  def handle_event("hold_random", _params, socket) do
    free_seats =
      socket.assigns.seats
      |> Enum.filter(fn {_num, state} -> state == :free end)
      |> Enum.map(fn {num, _} -> num end)

    case free_seats do
      [] ->
        {:noreply, put_flash(socket, :error, "На жаль, усі місця вже зайняті!")}

      seats_list ->
        seat = Enum.random(seats_list)
        handle_event("hold", %{"seat" => to_string(seat)}, socket)
    end
  end

  def handle_event("release_all_mine", _params, socket) do
    my_pid = self()

    my_seats =
      socket.assigns.seats
      |> Enum.filter(fn {_num, state} ->
        match?({:held, ^my_pid}, state) or match?({:confirmed, ^my_pid}, state)
      end)
      |> Enum.map(fn {num, _} -> num end)

    Enum.each(my_seats, fn seat ->
      SeatReservation.release(seat, my_pid)
    end)

    {:noreply, put_flash(socket, :info, "Всі ваші місця звільнено.")}
  end

  @impl true
  def handle_info({:seat_event, seat, event_type, fan}, socket) do
    new_state =
      case event_type do
        :held -> {:held, fan}
        :confirmed -> {:confirmed, fan}
        :released -> :free
      end

    updated_seats = Map.put(socket.assigns.seats, seat, new_state)

    event_item = %{
      id: System.unique_integer([:positive]),
      time: Time.utc_now() |> Time.truncate(:second) |> Time.to_string(),
      seat: seat,
      event: event_type,
      fan: inspect(fan),
      mine?: fan == self()
    }

    updated_log = Enum.take([event_item | socket.assigns.events_log], 12)

    {:noreply, assign(socket, seats: updated_seats, events_log: updated_log)}
  end

  @impl true
  def render(assigns) do
    total = SeatReservation.seat_count()
    free_count = Enum.count(assigns.seats, fn {_, s} -> s == :free end)
    held_count = Enum.count(assigns.seats, fn {_, s} -> match?({:held, _}, s) end)
    confirmed_count = Enum.count(assigns.seats, fn {_, s} -> match?({:confirmed, _}, s) end)

    my_held_seats =
      assigns.seats
      |> Enum.filter(fn {_, s} -> match?({:held, p} when p == assigns.my_pid, s) end)
      |> Enum.map(fn {num, _} -> num end)
      |> Enum.sort()

    my_confirmed_seats =
      assigns.seats
      |> Enum.filter(fn {_, s} -> match?({:confirmed, p} when p == assigns.my_pid, s) end)
      |> Enum.map(fn {num, _} -> num end)
      |> Enum.sort()

    assigns =
      assign(assigns,
        total: total,
        free_count: free_count,
        held_count: held_count,
        confirmed_count: confirmed_count,
        my_held_seats: my_held_seats,
        my_confirmed_seats: my_confirmed_seats
      )

    ~H"""
    <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
      <!-- Header -->
      <header class="mb-8 flex flex-col md:flex-row md:items-center md:justify-between border-b border-slate-800 pb-6">
        <div>
          <div class="flex items-center gap-3">
            <span class="inline-flex items-center justify-center p-2 bg-indigo-600 rounded-xl shadow-lg shadow-indigo-500/20 text-white font-bold text-xl">
              🎵
            </span>
            <h1 class="text-3xl font-extrabold tracking-tight bg-gradient-to-r from-white via-slate-200 to-indigo-300 bg-clip-text text-transparent">
              Сервер бронювання квитків на концерт
            </h1>
          </div>
          <p class="mt-2 text-sm text-slate-400">
            Інтерактивний моніторинг та вибір місць у режимі реального часу (Phoenix LiveView)
          </p>
        </div>

        <div class="mt-4 md:mt-0 flex items-center gap-3">
          <button
            phx-click="hold_random"
            class="px-4 py-2.5 bg-indigo-600 hover:bg-indigo-500 active:bg-indigo-700 text-white text-sm font-semibold rounded-lg shadow-md transition duration-150 flex items-center gap-2"
          >
            <span>⚡ Зайняти випадкове</span>
          </button>
          <%= if @my_held_seats != [] or @my_confirmed_seats != [] do %>
            <button
              phx-click="release_all_mine"
              class="px-4 py-2.5 bg-rose-600/20 hover:bg-rose-600/30 text-rose-300 border border-rose-500/30 text-sm font-semibold rounded-lg transition duration-150"
            >
              Звільнити мої місця
            </button>
          <% end %>
        </div>
      </header>

      <!-- Flash messages -->
      <%= if Phoenix.Flash.get(@flash, :info) do %>
        <div class="mb-6 p-4 rounded-xl bg-emerald-950/80 border border-emerald-500/30 text-emerald-300 text-sm flex items-center justify-between shadow-lg backdrop-blur">
          <div class="flex items-center gap-2">
            <span>✨</span>
            <span><%= Phoenix.Flash.get(@flash, :info) %></span>
          </div>
        </div>
      <% end %>

      <%= if Phoenix.Flash.get(@flash, :error) do %>
        <div class="mb-6 p-4 rounded-xl bg-rose-950/80 border border-rose-500/30 text-rose-300 text-sm flex items-center justify-between shadow-lg backdrop-blur">
          <div class="flex items-center gap-2">
            <span>⚠️</span>
            <span><%= Phoenix.Flash.get(@flash, :error) %></span>
          </div>
        </div>
      <% end %>

      <!-- Statistics Bar -->
      <div class="grid grid-cols-2 sm:grid-cols-4 gap-4 mb-8">
        <div class="bg-slate-900/80 border border-slate-800 rounded-2xl p-5 shadow-sm">
          <div class="text-xs font-medium uppercase tracking-wider text-slate-400">Усього місць</div>
          <div class="mt-2 text-2xl font-bold text-white"><%= @total %></div>
          <div class="mt-1 text-xs text-slate-500">10 рядів по 10 місць</div>
        </div>

        <div class="bg-slate-900/80 border border-emerald-900/40 rounded-2xl p-5 shadow-sm">
          <div class="text-xs font-medium uppercase tracking-wider text-emerald-400 flex items-center gap-1.5">
            <span class="w-2 h-2 rounded-full bg-emerald-500 animate-pulse"></span>
            Вільні
          </div>
          <div class="mt-2 text-2xl font-bold text-emerald-400"><%= @free_count %></div>
          <div class="mt-1 text-xs text-slate-500"><%= round(@free_count / @total * 100) %>% від загальної кількості</div>
        </div>

        <div class="bg-slate-900/80 border border-amber-900/40 rounded-2xl p-5 shadow-sm">
          <div class="text-xs font-medium uppercase tracking-wider text-amber-400 flex items-center gap-1.5">
            <span class="w-2 h-2 rounded-full bg-amber-500"></span>
            Утримані (Hold)
          </div>
          <div class="mt-2 text-2xl font-bold text-amber-400"><%= @held_count %></div>
          <div class="mt-1 text-xs text-slate-500">Таймаут 10 сек</div>
        </div>

        <div class="bg-slate-900/80 border border-indigo-900/40 rounded-2xl p-5 shadow-sm">
          <div class="text-xs font-medium uppercase tracking-wider text-indigo-400 flex items-center gap-1.5">
            <span class="w-2 h-2 rounded-full bg-indigo-500"></span>
            Підтверджені
          </div>
          <div class="mt-2 text-2xl font-bold text-indigo-400"><%= @confirmed_count %></div>
          <div class="mt-1 text-xs text-slate-500">Викуплені квитки</div>
        </div>
      </div>

      <!-- Main Section: Seat Grid & Controls / Log -->
      <div class="grid grid-cols-1 lg:grid-cols-3 gap-8">
        <!-- Seats Hall (2 cols) -->
        <div class="lg:col-span-2 bg-slate-900/90 border border-slate-800 rounded-3xl p-6 shadow-xl backdrop-blur">
          <div class="flex items-center justify-between mb-6 pb-4 border-b border-slate-800">
            <div>
              <h2 class="text-lg font-bold text-white">Схема залу</h2>
              <p class="text-xs text-slate-400">Натисніть на місце для вибору, резервування або підтвердження</p>
            </div>
            <!-- Legend -->
            <div class="flex items-center gap-3 text-xs">
              <div class="flex items-center gap-1.5">
                <span class="w-3 h-3 rounded bg-emerald-500/20 border border-emerald-500/60"></span>
                <span class="text-slate-300">Вільне</span>
              </div>
              <div class="flex items-center gap-1.5">
                <span class="w-3 h-3 rounded bg-amber-500/20 border border-amber-500/60"></span>
                <span class="text-slate-300">Утримане</span>
              </div>
              <div class="flex items-center gap-1.5">
                <span class="w-3 h-3 rounded bg-indigo-500/20 border border-indigo-500/60"></span>
                <span class="text-slate-300">Куплене</span>
              </div>
            </div>
          </div>

          <!-- Concert Stage visualization -->
          <div class="mb-8 text-center">
            <div class="w-3/4 mx-auto py-2 px-4 rounded-xl bg-gradient-to-b from-indigo-500/20 to-transparent border border-indigo-500/30 text-indigo-300 text-xs font-semibold tracking-widest uppercase shadow-[0_0_20px_rgba(99,102,241,0.15)]">
              🎤 СЦЕНА КОНЦЕРТУ 🎸
            </div>
          </div>

          <!-- Seat Grid (10x10) -->
          <div class="grid grid-cols-10 gap-2 sm:gap-2.5">
            <%= for seat_num <- 1..@total do %>
              <%
                state = Map.get(@seats, seat_num, :free)
                is_selected = @selected_seat == seat_num

                {bg_class, text_class, border_class, label} =
                  case state do
                    :free ->
                      {"bg-emerald-950/30 hover:bg-emerald-900/50 hover:scale-105 active:scale-95", "text-emerald-300", "border-emerald-500/40", "Вільне"}

                    {:held, fan} ->
                      if fan == @my_pid do
                        {"bg-amber-500/20 border-amber-400 ring-2 ring-amber-400/50 hover:scale-105", "text-amber-200 font-bold", "border-amber-400", "Ваш Hold (10с)"}
                      else
                        {"bg-amber-950/40 opacity-70 cursor-not-allowed", "text-amber-400/70", "border-amber-700/40", "Зайнято"}
                      end

                    {:confirmed, fan} ->
                      if fan == @my_pid do
                        {"bg-indigo-600/30 border-indigo-400 ring-2 ring-indigo-400/50", "text-indigo-200 font-bold", "border-indigo-400", "Ваше"}
                      else
                        {"bg-slate-800/60 opacity-60 cursor-not-allowed", "text-slate-400", "border-slate-700/50", "Куплено"}
                      end
                  end
              %>

              <button
                type="button"
                phx-click="select_seat"
                phx-value-seat={seat_num}
                title={"Місце ##{seat_num} — #{label}"}
                class={[
                  "aspect-square rounded-xl flex flex-col items-center justify-center p-1 text-xs font-medium border transition-all duration-150 cursor-pointer shadow-sm relative group",
                  bg_class,
                  text_class,
                  border_class,
                  is_selected && "ring-2 ring-white scale-105 shadow-lg"
                ]}
              >
                <span class="text-sm font-semibold"><%= seat_num %></span>
                <%= case state do %>
                  <% :free -> %>
                    <span class="w-1.5 h-1.5 rounded-full bg-emerald-400 mt-0.5"></span>
                  <% {:held, fan} when fan == @my_pid -> %>
                    <span class="w-1.5 h-1.5 rounded-full bg-amber-400 animate-ping mt-0.5"></span>
                  <% {:held, _} -> %>
                    <span class="w-1.5 h-1.5 rounded-full bg-amber-600 mt-0.5"></span>
                  <% {:confirmed, fan} when fan == @my_pid -> %>
                    <span class="text-[10px] leading-none">✓</span>
                  <% {:confirmed, _} -> %>
                    <span class="w-1.5 h-1.5 rounded-full bg-slate-500 mt-0.5"></span>
                <% end %>
              </button>
            <% end %>
          </div>
        </div>

        <!-- Sidebar: Selected Seat & Live Activity Feed (1 col) -->
        <div class="space-y-6">
          <!-- Selected Seat Action Card -->
          <div class="bg-slate-900/90 border border-slate-800 rounded-3xl p-6 shadow-xl backdrop-blur">
            <h3 class="text-base font-bold text-white mb-4 flex items-center justify-between">
              <span>Обране місце</span>
              <%= if @selected_seat do %>
                <span class="px-2.5 py-0.5 rounded-full text-xs font-semibold bg-indigo-500/20 text-indigo-300 border border-indigo-500/30">
                  #<%= @selected_seat %>
                </span>
              <% end %>
            </h3>

            <%= if @selected_seat do %>
              <%
                current_state = Map.get(@seats, @selected_seat, :free)
              %>
              <div class="space-y-4">
                <div class="p-4 rounded-2xl bg-slate-950/60 border border-slate-800/80">
                  <div class="text-xs text-slate-400">Статус місця</div>
                  <div class="mt-1 font-semibold text-lg flex items-center gap-2">
                    <%= case current_state do %>
                      <% :free -> %>
                        <span class="text-emerald-400 flex items-center gap-1.5">
                          <span class="w-2.5 h-2.5 rounded-full bg-emerald-400"></span>
                          Вільне для вибору
                        </span>
                      <% {:held, fan} when fan == @my_pid -> %>
                        <span class="text-amber-400 flex items-center gap-1.5">
                          <span class="w-2.5 h-2.5 rounded-full bg-amber-400 animate-pulse"></span>
                          Утримано вами (діє 10 сек)
                        </span>
                      <% {:held, _} -> %>
                        <span class="text-amber-500 flex items-center gap-1.5">
                          <span class="w-2.5 h-2.5 rounded-full bg-amber-600"></span>
                          Утримується іншим користувачем
                        </span>
                      <% {:confirmed, fan} when fan == @my_pid -> %>
                        <span class="text-indigo-400 flex items-center gap-1.5">
                          <span class="w-2.5 h-2.5 rounded-full bg-indigo-400"></span>
                          Успішно підтверджено вами
                        </span>
                      <% {:confirmed, _} -> %>
                        <span class="text-slate-400 flex items-center gap-1.5">
                          <span class="w-2.5 h-2.5 rounded-full bg-slate-500"></span>
                          Оплачено іншим фанатом
                        </span>
                    <% end %>
                  </div>
                </div>

                <!-- Actions depending on seat state -->
                <div class="space-y-2">
                  <%= case current_state do %>
                    <% :free -> %>
                      <button
                        phx-click="hold"
                        phx-value-seat={@selected_seat}
                        class="w-full py-3 bg-emerald-600 hover:bg-emerald-500 active:bg-emerald-700 text-white font-semibold rounded-xl shadow-lg shadow-emerald-600/20 transition flex items-center justify-center gap-2"
                      >
                        🔒 Зарезервувати (Hold 10s)
                      </button>

                    <% {:held, fan} when fan == @my_pid -> %>
                      <button
                        phx-click="confirm"
                        phx-value-seat={@selected_seat}
                        class="w-full py-3 bg-indigo-600 hover:bg-indigo-500 active:bg-indigo-700 text-white font-semibold rounded-xl shadow-lg shadow-indigo-600/20 transition flex items-center justify-center gap-2"
                      >
                        ✅ Підтвердити покупку
                      </button>
                      <button
                        phx-click="release"
                        phx-value-seat={@selected_seat}
                        class="w-full py-2.5 bg-slate-800 hover:bg-slate-700 text-slate-300 font-medium rounded-xl border border-slate-700 transition"
                      >
                        Звільнити місце
                      </button>

                    <% {:confirmed, fan} when fan == @my_pid -> %>
                      <button
                        phx-click="release"
                        phx-value-seat={@selected_seat}
                        class="w-full py-2.5 bg-rose-600/20 hover:bg-rose-600/30 text-rose-300 font-medium rounded-xl border border-rose-500/30 transition"
                      >
                        Скасувати бронь
                      </button>

                    <% _ -> %>
                      <div class="text-xs text-slate-500 text-center py-2">
                        Місце недоступне для дій
                      </div>
                  <% end %>
                </div>
              </div>
            <% else %>
              <div class="text-center py-8 text-slate-500 text-sm">
                Оберіть місце на схемі залу, щоб забронювати або підтвердити його.
              </div>
            <% end %>
          </div>

          <!-- Live Activity Log -->
          <div class="bg-slate-900/90 border border-slate-800 rounded-3xl p-6 shadow-xl backdrop-blur">
            <h3 class="text-base font-bold text-white mb-3 flex items-center justify-between">
              <span>Потік подій у реальному часі</span>
              <span class="w-2 h-2 rounded-full bg-emerald-400 animate-ping"></span>
            </h3>

            <div class="space-y-2 max-h-72 overflow-y-auto pr-1">
              <%= if @events_log == [] do %>
                <div class="text-xs text-slate-500 text-center py-6">
                  Очікування подій від сервера...
                </div>
              <% else %>
                <%= for ev <- @events_log do %>
                  <div class={[
                    "p-2.5 rounded-xl border text-xs flex items-center justify-between transition",
                    ev.mine? && "bg-indigo-950/40 border-indigo-500/40",
                    !ev.mine? && "bg-slate-950/40 border-slate-800/80"
                  ]}>
                    <div class="flex items-center gap-2">
                      <span class={[
                        "w-2 h-2 rounded-full",
                        ev.event == :held && "bg-amber-400",
                        ev.event == :confirmed && "bg-indigo-400",
                        ev.event == :released && "bg-emerald-400"
                      ]}></span>
                      <span class="font-semibold text-slate-200">Місце #<%= ev.seat %></span>
                      <span class="text-slate-400">
                        <%= case ev.event do %>
                          <% :held -> %> утримано
                          <% :confirmed -> %> підтверджено
                          <% :released -> %> звільнено
                        <% end %>
                      </span>
                    </div>
                    <div class="flex items-center gap-2">
                      <%= if ev.mine? do %>
                        <span class="text-[10px] px-1.5 py-0.5 rounded bg-indigo-500/30 text-indigo-300">Ви</span>
                      <% end %>
                      <span class="text-[10px] text-slate-500 font-mono"><%= ev.time %></span>
                    </div>
                  </div>
                <% end %>
              <% end %>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end
end
