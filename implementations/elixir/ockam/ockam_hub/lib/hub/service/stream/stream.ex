defmodule Ockam.Hub.Service.Stream do
  @moduledoc false

  use Ockam.Worker
  use Ockam.MessageProtocol

  alias Ockam.Hub.Service.Stream.Instance

  alias Ockam.Message

  require Logger

  @type state() :: map()

  @impl true
  def protocol_mapping() do
    Ockam.Protocol.mapping([
      {:server, Ockam.Protocol.Stream.Create},
      {:server, Ockam.Protocol.Error}
    ])
  end

  @impl true
  def setup(options, state) do
    stream_options = Keyword.get(options, :stream_options, [])
    {:ok, Map.put(state, :stream_options, stream_options)}
  end

  @impl true
  def handle_message(%{payload: payload} = message, state) do
    state =
      case decode_payload(payload) do
        {:ok, "stream_create", %{stream_name: name}} ->
          ensure_stream(name, message, state)

        {:error, error} ->
          return_error(error, message, state)
      end

    {:ok, state}
  end

  def return_error(error, message, state) do
    Logger.error("Error creating stream: #{inspect(error)}")

    Ockam.Router.route(%{
      onward_route: Message.return_route(message),
      return_route: [state.address],
      payload: encode_payload("error", %{reason: "Invalid request"})
    })
  end

  @spec ensure_stream(String.t(), map(), state()) :: state()
  def ensure_stream(name, message, state) do
    case find_stream(name, state) do
      {:ok, stream} ->
        notify_create(stream, message, state)

      :error ->
        create_stream(name, message, state)
    end
  end

  @spec find_stream(String.t(), state()) :: {:ok, pid()} | :error
  def find_stream(name, state) do
    streams = Map.get(state, :streams, %{})
    Map.fetch(streams, name)
  end

  @spec register_stream(String.t(), String.t(), state()) :: state()
  def register_stream(name, address, state) do
    ## TODO: maybe use address in the registry?
    case Ockam.Node.whereis(address) do
      nil ->
        raise("Stream not found on address #{address}")

      pid when is_pid(pid) ->
        streams = Map.get(state, :streams, %{})
        Map.put(state, :streams, Map.put(streams, name, pid))
    end
  end

  @spec notify_create(pid(), map(), state()) :: state()
  def notify_create(stream, message, state) do
    return_route = Message.return_route(message)
    Instance.notify(stream, return_route)
    state
  end

  @spec create_stream(String.t(), map(), state()) :: state()
  def create_stream(create_name, message, state) do
    name =
      case create_name do
        :undefined ->
          create_stream_name(state)

        _defined ->
          create_name
      end

    return_route = Message.return_route(message)
    stream_options = Map.get(state, :stream_options, [])

    {:ok, address} =
      Instance.create(
        stream_options ++
          [
            reply_route: return_route,
            stream_name: name
          ]
      )

    register_stream(name, address, state)
  end

  def create_stream_name(state) do
    random_string = "generated_" <> Base.encode16(:crypto.strong_rand_bytes(4), case: :lower)

    case find_stream(random_string, state) do
      {:ok, _} -> create_stream_name(state)
      :error -> random_string
    end
  end
end
