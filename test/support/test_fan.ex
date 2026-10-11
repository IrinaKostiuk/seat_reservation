defmodule SeatReservation.TestFan do
  @moduledoc """
  A long-lived process standing in for a fan in tests.

  The server only accepts a request from the fan it is about, so tests run fan
  actions inside this process. A fan exits when the process that started it
  exits.
  """

  alias SeatReservation.Server

  @doc "Starts a fan owned by the calling process."
  @spec start() :: pid
  def start do
    owner = self()
    spawn(fn -> loop(Process.monitor(owner)) end)
  end

  @doc "Runs `fun` inside `fan`. Returns its result, or `{:exit, reason}` if the call exited."
  @spec run(pid, (-> result)) :: result | {:exit, term} when result: term
  def run(fan, fun) do
    monitor = Process.monitor(fan)
    ref = make_ref()
    send(fan, {:run, self(), ref, fun})

    receive do
      {^ref, result} ->
        Process.demonitor(monitor, [:flush])
        result

      {:DOWN, ^monitor, :process, _pid, reason} ->
        raise "fan #{inspect(fan)} exited: #{inspect(reason)}"
    end
  end

  @spec hold(pid, GenServer.server(), term) :: term
  def hold(fan, server, seat), do: run(fan, fn -> Server.hold(server, seat, fan) end)

  @spec confirm(pid, GenServer.server(), term) :: term
  def confirm(fan, server, seat), do: run(fan, fn -> Server.confirm(server, seat, fan) end)

  @spec release(pid, GenServer.server(), term) :: term
  def release(fan, server, seat), do: run(fan, fn -> Server.release(server, seat, fan) end)

  @spec subscribe(pid, GenServer.server()) :: term
  def subscribe(fan, server), do: run(fan, fn -> Server.subscribe(server) end)

  defp loop(owner) do
    receive do
      {:run, caller, ref, fun} ->
        send(caller, {ref, safely(fun)})
        loop(owner)

      {:DOWN, ^owner, :process, _pid, _reason} ->
        :ok
    end
  end

  defp safely(fun) do
    fun.()
  catch
    :exit, reason -> {:exit, reason}
  end
end
