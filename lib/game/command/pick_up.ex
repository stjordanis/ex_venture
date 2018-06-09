defmodule Game.Command.PickUp do
  @moduledoc """
  The "pick up" command
  """

  use Game.Command
  use Game.Currency

  require Logger

  alias Game.Environment.State.Overworld
  alias Game.Items

  @must_be_alive true

  commands([{"pick up", ["get", "take"]}], parse: false)

  @impl Game.Command
  def help(:topic), do: "Pick Up"
  def help(:short), do: "Pick up an item in the same room"

  def help(:full) do
    """
    #{help(:short)}.

    Example:
    [ ] > {command}pick up sword{/command}
    """
  end

  @impl Game.Command
  @doc """
  Parse the command into arguments

      iex> Game.Command.PickUp.parse("pick up")
      {"pick up", :help}
      iex> Game.Command.PickUp.parse("get")
      {"get", :help}
      iex> Game.Command.PickUp.parse("take")
      {"take", :help}

      iex> Game.Command.PickUp.parse("pick up item")
      {"item"}
      iex> Game.Command.PickUp.parse("pick up all")
      {:all}

      iex> Game.Command.PickUp.parse("get item")
      {"item"}
      iex> Game.Command.PickUp.parse("get all")
      {:all}

      iex> Game.Command.PickUp.parse("take item")
      {"item"}
      iex> Game.Command.PickUp.parse("take all")
      {:all}

      iex> Game.Command.PickUp.parse("unknown")
      {:error, :bad_parse, "unknown"}
  """
  def parse(command)
  def parse("pick up"), do: {"pick up", :help}
  def parse("get"), do: {"get", :help}
  def parse("take"), do: {"take", :help}
  def parse("pick up all"), do: {:all}
  def parse("get all"), do: {:all}
  def parse("take all"), do: {:all}
  def parse("pick up " <> item), do: {item}
  def parse("get " <> item), do: {item}
  def parse("take " <> item), do: {item}

  @impl Game.Command
  @doc """
  Pick up an item from a room
  """
  def run(command, state)

  def run({@currency}, state) do
    case pick_up_currency(state) do
      {:ok, currency, state} ->
        state.socket |> @socket.echo("You picked up #{currency} #{@currency}")
        {:update, state}

      {:error, :no_currency, _state} ->
        state.socket |> @socket.echo(~s(There was no #{@currency} to be found.))

      {:error, :could_not_pickup} ->
        state.socket |> @socket.echo(~s("#{@currency}" could not be found))
    end
  end

  def run({:all}, state) do
    %{save: save} = state
    {:ok, room} = @environment.look(save.room_id)

    with {:ok, state} <- pick_up_all_items(state, room),
         {:ok, currency, state} <- pick_up_currency(state) do
      state.socket |> @socket.echo("You picked up #{currency} #{@currency}")
      {:update, state}
    else
      {:error, :no_currency, state} ->
        {:update, state}

      {:error, :could_not_pickup} ->
        {:update, state}

      {:error, :overworld} ->
        state.socket |> @socket.echo("There was nothing to pick up")
    end
  end

  def run({item_name}, state = %{save: save}) do
    {:ok, room} = @environment.look(save.room_id)

    with {:ok, instance} <- find_item(room, item_name),
         {:ok, item, state} <- pick_up(instance, room, state) do
      state.socket |> @socket.echo("You picked up the #{Format.item_name(item)}")
      {:update, state}
    else
      {:error, :not_found} ->
        state.socket |> @socket.echo(~s("#{item_name}" could not be found))

      {:error, :could_not_pickup, item} ->
        state.socket |> @socket.echo(~s("#{item.name}" could not be found))
    end
  end

  def run({verb, :help}, %{socket: socket}) do
    message =
      "You don't know what to #{verb}. See {command}help get{/command} for more information."

    socket |> @socket.echo(message)
  end

  defp pick_up_all_items(_state, _room = %Overworld{}), do: {:error, :overworld}

  defp pick_up_all_items(state, room) do
    state =
      Enum.reduce(room.items, state, fn item, state ->
        case pick_up(item, room, state) do
          {:ok, item, state} ->
            state.socket |> @socket.echo("You picked up the #{Format.item_name(item)}")

            state

          _ ->
            state
        end
      end)

    {:ok, state}
  end

  defp find_item(_room = %Overworld{}, _item_name), do: {:error, :not_found}

  defp find_item(room, item_name) do
    instance =
      room.items
      |> Enum.find(fn instance ->
        item = Items.item(instance)
        Game.Item.matches_lookup?(item, item_name)
      end)

    case instance do
      nil ->
        {:error, :not_found}

      instance ->
        {:ok, instance}
    end
  end

  @doc """
  Pick up an item from a room
  """
  def pick_up(item, room, state = %{save: save}) do
    case @environment.pick_up(room.id, item) do
      {:ok, instance} ->
        item = Items.item(instance)

        Logger.info(
          "Session (#{inspect(self())}) picking up item (#{item.id}) from room (#{room.id})",
          type: :player
        )

        save = %{save | items: [instance | save.items]}
        {:ok, item, Map.put(state, :save, save)}

      _ ->
        {:error, :could_not_pickup, item}
    end
  end

  defp pick_up_currency(state) do
    %{save: save} = state

    case @environment.pick_up_currency(save.room_id) do
      {:ok, currency} ->
        Logger.info(
          "Session (#{inspect(self())}) picking up #{currency} currency from room (#{save.room_id})",
          type: :player
        )

        save = %{save | currency: save.currency + currency}
        {:ok, currency, Map.put(state, :save, save)}

      {:error, :no_currency} ->
        {:error, :no_currency, state}

      _ ->
        {:error, :could_not_pickup}
    end
  end
end
