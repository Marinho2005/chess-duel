defmodule ChessDuelBackend.Broadcasts.AnalysisTest do
  use ExUnit.Case, async: false

  alias ChessDuelBackend.Broadcasts.Analysis

  test "avalia cada ply uma vez, publica o resultado e reutiliza o cache" do
    parent = self()
    moves = [%{from: "e2", to: "e4", promotion: nil}]

    server =
      start_supervised!(
        {Analysis,
         name: nil,
         game_provider: fn
           "broadcast-1" -> {:ok, %{moves: moves}}
           _game_id -> :error
         end,
         evaluator: fn selected_moves ->
           send(parent, {:evaluated, selected_moves})

           {:ok,
            %{
              evaluation: %{"type" => "cp", "value" => 34},
              principal_variation: ["e7e5", "g1f3"]
            }}
         end}
      )

    Phoenix.PubSub.subscribe(ChessDuelBackend.PubSub, "broadcast_watch:broadcast-1")

    assert {:pending, 1} = Analysis.request("broadcast-1", 1, server)
    assert_receive {:evaluated, ^moves}

    assert_receive %Phoenix.Socket.Broadcast{
      event: "broadcast_evaluation",
      payload: %{
        ply: 1,
        evaluation: %{"type" => "cp", "value" => 34},
        principal_variation: ["e7e5", "g1f3"]
      }
    }

    assert {:ok,
            %{
              evaluation: %{"type" => "cp", "value" => 34},
              principal_variation: ["e7e5", "g1f3"]
            }} =
             Analysis.request("broadcast-1", 1, server)

    refute_receive {:evaluated, _moves}
  end

  test "recusa broadcast inexistente e ply fora da partida" do
    server =
      start_supervised!(
        {Analysis,
         name: nil,
         game_provider: fn
           "broadcast-1" -> {:ok, %{moves: []}}
           _game_id -> :error
         end,
         evaluator: fn _moves ->
           {:ok, %{evaluation: %{"type" => "cp", "value" => 0}, principal_variation: []}}
         end}
      )

    assert {:error, :broadcast_not_found} = Analysis.request("missing", 0, server)
    assert {:error, :invalid_ply} = Analysis.request("broadcast-1", 1, server)
  end
end
