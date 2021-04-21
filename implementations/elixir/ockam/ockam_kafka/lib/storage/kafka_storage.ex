defmodule Ockam.Hub.Service.Stream.Storage.Kafka do
  @moduledoc """
    Kafka storage backend for ockam stream service
  """
  @behaviour Ockam.Hub.Service.Stream.Storage

  require Logger

  @type options() :: Keyword.t()
  @type message() :: %{index: integer(), data: binary()}

  @default_worker :ockam

  ## Storage API
  @spec init(String.t(), options()) :: :ok | {:error, any()}
  def init(stream_name, options) do
    request = create_topics_request(stream_name, options)
    worker_name = worker_name(options)
    no_error = topic_error_none(request)
    topic_already_exists = topic_error_exists(request)
    Logger.info("Kafka storage init")

    ## TODO: fail if unable to create the worker
    create_kafka_worker(options)

    case KafkaEx.create_topics([request], worker_name: worker_name) do
      %KafkaEx.Protocol.CreateTopics.Response{
        topic_errors: [^no_error]
      } ->
        {:ok, options}

      %KafkaEx.Protocol.CreateTopics.Response{
        topic_errors: [^topic_already_exists]
      } ->
        Logger.info("Using existing topic")
        {:ok, options}

      other ->
        ## TODO: parse the error
        Logger.error("Create topic error #{inspect(other)}")
        {:error, other}
    end
  end

  @spec save(String.t(), binary(), options()) :: {{:ok, integer()} | {:error, any()}, options()}
  def save(stream_name, message, options) do
    request = produce_request(stream_name, message, options)
    worker_name = worker_name(options)

    result =
      case KafkaEx.produce(request, worker_name: worker_name) do
        :ok ->
          {:ok, 0}

        {:ok, index} ->
          {:ok, index}

        {:error, err} ->
          {:error, err}

        other ->
          Logger.error("Unexpected result from produce: #{inspect(other)}")
          {:error, {:save_response, other}}
      end

    {result, options}
  end

  @spec fetch(String.t(), integer(), integer(), options()) ::
          {{:ok, [message()]} | {:error, any()}, options()}
  def fetch(stream_name, index, limit, options) do
    topic = topic(stream_name, options)
    partition = partition(stream_name, index, limit, options)
    fetch_options = fetch_options(stream_name, index, limit, options)

    {fetch_messages(limit, topic, partition, fetch_options), options}
  end

  defp fetch_messages(limit, topic, partition, fetch_options, previous \\ []) do
    prev_count = Enum.count(previous)

    case KafkaEx.fetch(topic, partition, fetch_options) do
      :topic_not_found ->
        {:error, :topic_not_found}

      [%KafkaEx.Protocol.Fetch.Response{topic: topic} = fetch_response] ->
        messages = get_response_messages(fetch_response)

        case Enum.count(messages) do
          0 ->
            {:ok, previous}

          num when num + prev_count >= limit ->
            {:ok, previous ++ Enum.take(messages, limit)}

          _ ->
            last_index = last_index(messages)
            fetch_options = fetch_options(fetch_options, last_index + 1)
            fetch_messages(limit, topic, partition, fetch_options, previous ++ messages)
        end

      other ->
        Logger.error("Unexpected fetch response #{inspect(other)}")
        {:error, {:fetch_response, other}}
    end
  end

  def get_response_messages(%KafkaEx.Protocol.Fetch.Response{partitions: partitions}) do
    partitions
    |> Enum.flat_map(fn partition ->
      partition
      |> Map.get(:message_set, [])
      |> Enum.map(fn %{offset: offset, value: value} -> %{index: offset, data: value} end)
    end)
    |> Enum.sort_by(fn %{index: index} -> index end)
  end

  def last_index(messages) do
    messages
    |> Enum.map(fn %{index: index} -> index end)
    |> Enum.max()
  end

  def create_kafka_worker(options) do
    worker_name = worker_name(options)
    Logger.info("Create worker #{inspect(options)} #{inspect(worker_name)}")
    ## TODO: pass worker config
    result = KafkaEx.create_worker(worker_name)
    Logger.info("KafkaEx config #{inspect(Application.get_all_env(:kafka_ex))}")
    Logger.info("Create worker result #{inspect(result)}")
  end

  defp worker_name(options) do
    Keyword.get(options, :worker_name, @default_worker)
  end

  defp create_topics_request(stream_name, options) do
    topic = topic(stream_name, options)
    %KafkaEx.Protocol.CreateTopics.TopicRequest{topic: topic}
  end

  defp topic_error_none(topic_request) do
    %KafkaEx.Protocol.CreateTopics.TopicError{
      topic_name: topic_request.topic,
      error_code: :no_error
    }
  end

  defp topic_error_exists(topic_request) do
    %KafkaEx.Protocol.CreateTopics.TopicError{
      topic_name: topic_request.topic,
      error_code: :topic_already_exists
    }
  end

  defp produce_request(stream_name, message, options) do
    topic = topic(stream_name, options)

    %KafkaEx.Protocol.Produce.Request{
      topic: topic,
      partition: 0,
      required_acks: 1,
      messages: [%KafkaEx.Protocol.Produce.Message{value: message}]
    }
  end

  defp topic(stream_name, _options) do
    stream_name
  end

  defp partition(_stream_name, _index, _limit, _options) do
    0
  end

  defp fetch_options(_stream_name, index, limit, options) do
    [
      worker_name: worker_name(options),
      offset: index,
      auto_commit: false,
      ## Assume messages are 1Kb or so.
      max_bytes: limit * 1024
    ]
  end

  defp fetch_options(options, last_index) do
    Keyword.put(options, :offset, last_index)
  end
end
