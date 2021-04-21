defmodule Ockam.Hub.Service.Stream.Index.KafkaOffset do
  @moduledoc """
    Kafka storage backend for ockam stream index service
    Using kafka offset storage
  """
  @behaviour Ockam.Hub.Service.Stream.Index
  @default_worker :kafka_index_worker

  alias KafkaEx.Protocol.OffsetCommit
  alias KafkaEx.Protocol.OffsetFetch

  require Logger

  def init(options) do
    ## TODO: fail if unable to create the worker
    create_kafka_worker(options)
    {:ok, options}
  end

  @impl true
  def get_index(client_id, stream_name, options) do
    worker_name = worker_name(options)
    request = get_index_request(client_id, stream_name, options)
    topic = Map.get(request, :topic)

    result = case KafkaEx.offset_fetch(worker_name, request) do
      [
        %OffsetFetch.Response{
          topic: ^topic,
          partitions: [partition_response]
        }
      ] ->
        case Map.get(partition_response, :error_code) do
          :no_error ->
            {:ok, Map.get(partition_response, :offset)}

          :unknown_topic_or_partition ->
            {:ok, :undefined}

          other ->
            {:error, {:get_error, other}}
        end

      other ->
        {:error, {:get_error, other}}
    end
    {result, options}
  end

  @impl true
  def save_index(client_id, stream_name, index, options) do
    worker_name = worker_name(options)
    request = save_index_request(client_id, stream_name, index, options)
    topic = Map.get(request, :topic)
    partition = Map.get(request, :partition)

    result = case KafkaEx.offset_commit(worker_name, request) do
      [%OffsetCommit.Response{partitions: [^partition], topic: ^topic}] ->
        :ok

      other ->
        {:error, {:save_error, other}}
    end
    {result, options}
  end

  def get_index_request(client_id, stream_name, _options) do
    ## TODO: topic/partition
    %OffsetFetch.Request{
      consumer_group: client_id,
      topic: stream_name,
      partition: 0
    }
  end

  def save_index_request(client_id, stream_name, index, _options) do
    %OffsetCommit.Request{
      consumer_group: client_id,
      topic: stream_name,
      partition: 0,
      offset: index
    }
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
end
