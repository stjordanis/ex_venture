defmodule Data.Events.StateTicked do
  @moduledoc """
  `state/ticked` event
  """

  @event_type "state/ticked"

  @derive Jason.Encoder
  defstruct [:id, :actions, options: %{}, type: @event_type]

  @behaviour Data.Events

  @impl true
  def type(), do: @event_type

  @impl true
  def allowed_actions(), do: ["commands/emote", "commands/move", "commands/say"]

  @impl true
  def options(), do: [room_id: :integer, minimum_delay: :float, random_delay: :float]
end
