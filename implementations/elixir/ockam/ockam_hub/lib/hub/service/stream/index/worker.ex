defmodule Ockam.Hub.Service.Stream.Index.Worker do
  @moduledoc false

  use Ockam.MessageProtocol
  use Ockam.Worker

  require Logger

  @default_mod Ockam.Hub.Service.Stream.Index.Internal
  @protocol "stream_index"

  @impl true
  def protocol_mapping() do
    Ockam.Protocol.server(Ockam.Protocol.Stream.Index)
  end

  @impl true
  def setup(options, state) do
    storage_mod = Keyword.get(options, :storage_mod, @default_mod)
    storage_options = Keyword.get(options, :storage_options, [])

    case storage_mod.init(storage_options) do
      {:ok, storage_state} ->
        {:ok, Map.put(state, :storage, storage_state)}
      {:error, err} ->
        {:error, err}
    end
  end

  @impl true
  def handle_message(%{payload: payload} = message, state) do
    case decode_payload(payload) do
      {:ok, @protocol, {:save, data}} ->
        %{client_id: client_id, stream_name: stream_name, index: index} = data
        Logger.info("Save index #{inspect({client_id, stream_name, index})}")
        case save_index(client_id, stream_name, index, state) do
          {:ok, state} ->
            {:ok, state}
          {{:error, error}, _state} ->
            Logger.error("Unable to save index: #{inspect(data)}. Reason: #{inspect(error)}")
            {:error, error}
        end

      {:ok, @protocol, {:get, data}} ->
        %{client_id: client_id, stream_name: stream_name} = data
        Logger.info("get index #{inspect({client_id, stream_name})}")
        case get_index(client_id, stream_name, state) do
          {{:ok, index}, state} ->
            reply_index(client_id, stream_name, index, Ockam.Message.return_route(message), state)
            {:ok, state}
          {{:error, error}, _state} ->
            Logger.error("Unable to get index for: #{inspect(data)}. Reason: #{inspect(error)}")
            {:error, error}
        end

      {:error, other} ->
        Logger.error("Unexpected message #{inspect(other)}")
        {:ok, state}
    end
  end

  def save_index(client_id, stream_name, index, state) do
    with_storage(state, fn(storage_mod, storage_state) ->
      storage_mod.save_index(client_id, stream_name, index, storage_state)
    end)
  end

  def get_index(client_id, stream_name, state) do
    with_storage(state, fn(storage_mod, storage_state) ->
      storage_mod.get_index(client_id, stream_name, storage_state)
    end)
  end

  def with_storage(state, fun) do
    {storage_mod, storage_state} = Map.get(state, :storage)
    {result, new_storage_state} = fun.(storage_mod, storage_state)
    {result, Map.put(state, :storage, {storage_mod, new_storage_state})}
  end

  def reply_index(client_id, stream_name, index, return_route, state) do
    Ockam.Router.route(%{
      onward_route: return_route,
      return_route: [state.address],
      payload:
        encode_payload(@protocol, %{
          client_id: client_id,
          stream_name: stream_name,
          index: index
        })
    })
  end
end
