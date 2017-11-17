defmodule ExBanking.Router do
  @moduledoc """
  Router is responsible for supervising a pool of workers, each registered by its own number.
  """

  use Supervisor

  @pool_size 10

  def start_link(_) do
    Supervisor.start_link(__MODULE__, [], name: __MODULE__)
  end

  def init(_) do
    workers = for worker_id <- 1..@pool_size do
      Supervisor.child_spec({ExBanking.Worker, worker_id}, id: worker_id)
    end

    Supervisor.init(workers, strategy: :one_for_one)
  end

  @doc """
  Determnistically routes anything to one particular worker from the pool 
  """
  @spec choose_worker(key :: any) :: number
  def choose_worker(key) do
    :erlang.phash2(key, @pool_size) + 1
  end
end