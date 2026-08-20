defmodule ChessDuelBackend.ChessValidator do
  @moduledoc """
  Valida lances usando chess.js em um processo Node.js persistente.

  Node.js deve estar instalado no ambiente. Antes de iniciar o backend, instale
  as dependencias com `cd backend/priv/chess_validator && npm install`.
  """

  use GenServer

  require Logger

  @timeout 5_000

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def validate_move(fen, from, to, promotion \\ nil) do
    GenServer.call(__MODULE__, {:validate_move, fen, from, to, promotion}, @timeout + 1_000)
  end

  @impl true
  def init(_opts) do
    with node when is_binary(node) <- System.find_executable("node"),
         script <- Application.app_dir(:chess_duel_backend, "priv/chess_validator/validator.js"),
         true <- File.exists?(script) do
      port =
        Port.open({:spawn_executable, node}, [
          :binary,
          :exit_status,
          {:line, 65_536},
          args: [script]
        ])

      Logger.info("Chess validator Port opened successfully")
      {:ok, %{port: port}}
    else
      nil -> {:stop, "Node.js executable was not found"}
      false -> {:stop, "chess validator script was not found"}
    end
  end

  @impl true
  def handle_call({:validate_move, fen, from, to, promotion}, _from, %{port: port} = state) do
    request = Jason.encode!(%{fen: fen, from: from, to: to, promotion: promotion})
    true = Port.command(port, request <> "\n")

    case await_response(port) do
      {:port_exit, status} ->
        {:stop, {:validator_exit, status}, {:error, :validator_unavailable}, state}

      reply ->
        {:reply, reply, state}
    end
  end

  @impl true
  def handle_info({port, {:exit_status, status}}, %{port: port} = state) do
    {:stop, {:validator_exit, status}, state}
  end

  defp await_response(port) do
    receive do
      {^port, {:data, {:eol, line}}} -> decode_response(line)
      {^port, {:data, {:noeol, _partial}}} -> {:error, :validator_response_too_long}
      {^port, {:exit_status, status}} -> {:port_exit, status}
    after
      @timeout -> {:error, :validator_timeout}
    end
  end

  defp decode_response(line) do
    case Jason.decode(line) do
      {:ok, %{"valid" => true} = result} ->
        {:ok,
         %{
           new_fen: result["new_fen"],
           is_check: result["is_check"],
           is_checkmate: result["is_checkmate"],
           is_stalemate: result["is_stalemate"],
           is_draw: result["is_draw"],
           captured: result["captured"]
         }}

      {:ok, %{"valid" => false, "reason" => "illegal_move"}} ->
        {:error, :illegal_move}

      _ ->
        {:error, :invalid_validator_response}
    end
  end
end
