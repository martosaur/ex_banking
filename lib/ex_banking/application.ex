defmodule ExBanking.Application do
  @moduledoc false

  use Application

  def start(_type, _args) do
    ExBanking.Storage.create_table

    children = [
      Mutex.child_spec(ExBanking.Lock),
      {Registry, keys: :unique, name: ExBanking.Registry},
      {ExBanking.Router, []},
    ]

    opts = [strategy: :one_for_one, name: ExBanking.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
