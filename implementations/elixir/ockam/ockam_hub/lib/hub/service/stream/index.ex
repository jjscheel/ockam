defmodule Ockam.Hub.Service.Stream.Index do
  @moduledoc false

  @type options() :: Keyword.t()
  @type state() :: any()

  @callback init(options()) :: {:ok, state()} | {:error, any()}
  @callback get_index(client_id :: binary(), stream_name :: binary(), state()) :: {{:ok, integer()} | {:error, any()}, state()}
  @callback save_index(client_id :: binary(), stream_name :: binary(), index :: integer(), state()) :: {:ok | {:error, any()}, state()}
end
