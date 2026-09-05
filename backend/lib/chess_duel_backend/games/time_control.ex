defmodule ChessDuelBackend.Games.TimeControl do
  @moduledoc "Formatos de tempo aceitos nos desafios e partidas."

  @default_id "blitz_3_0"
  @controls %{
    "bullet_1_0" => %{
      id: "bullet_1_0",
      label: "Bullet 1+0",
      initial_time_ms: 60_000,
      increment_ms: 0
    },
    "blitz_3_0" => %{id: "blitz_3_0", label: "Blitz 3+0", initial_time_ms: 180_000, increment_ms: 0},
    "blitz_5_0" => %{
      id: "blitz_5_0",
      label: "Blitz 5+0",
      initial_time_ms: 300_000,
      increment_ms: 0
    },
    "rapid_10_0" => %{
      id: "rapid_10_0",
      label: "Rapid 10+0",
      initial_time_ms: 600_000,
      increment_ms: 0
    }
  }

  def default, do: Map.fetch!(@controls, @default_id)
  def all, do: Map.values(@controls)

  def fetch(id) when is_binary(id) do
    case Map.fetch(@controls, id) do
      {:ok, control} -> {:ok, control}
      :error -> {:error, :invalid_time_control}
    end
  end

  def fetch(_id), do: {:error, :invalid_time_control}

  def from_values(initial_time_ms, increment_ms)
      when is_integer(initial_time_ms) and is_integer(increment_ms) do
    Enum.find(Map.values(@controls), fn control ->
      control.initial_time_ms == initial_time_ms and control.increment_ms == increment_ms
    end) ||
      %{
        id: "custom_#{initial_time_ms}_#{increment_ms}",
        label: format_label(initial_time_ms, increment_ms),
        initial_time_ms: initial_time_ms,
        increment_ms: increment_ms
      }
  end

  def rating_category(60_000, 0), do: :bullet
  def rating_category(180_000, 0), do: :blitz
  def rating_category(300_000, 0), do: :blitz
  def rating_category(600_000, 0), do: :rapid
  def rating_category(_, _), do: :blitz

  def rating_category(%{initial_time_ms: initial, increment_ms: increment}),
    do: rating_category(initial, increment)

  defp format_label(initial_time_ms, increment_ms) do
    "#{div(initial_time_ms, 60_000)}+#{div(increment_ms, 1_000)}"
  end
end
