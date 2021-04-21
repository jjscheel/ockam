import Config

config :logger, level: :info

config :kafka_ex,
  disable_default_worker: true

import_config "#{Mix.env()}.exs"
