defmodule ExBanking.Worker do
  @moduledoc """
  Worker that does the job. Every single user or pair of users are guaranteed to be routed to a single worker.
  """

  use GenServer
  require Logger

  def start_link(worker_id) do
    GenServer.start_link(__MODULE__, [], name: via_tuple(worker_id))
  end

  def init(_) do
    send(self(), :init)
    {:ok, nil}
  end

  defp via_tuple(worker_id) do
    {:via, Registry, {ExBanking.Registry, worker_id}}
  end

  def handle_call({:add_action, user, action}, from, _state) do
    lock = Mutex.await(ExBanking.Lock, user)
    result = with {^user, balance, queue} <- ExBanking.Storage.get_user_from_storage(user),
         :ok <- ExBanking.Helper.validate_queue(queue) do
      ExBanking.Storage.save_user_to_storage({user, balance, queue ++ [{action, from}]})
      send(self(), {:process, user})
      {:reply, :ok, nil}
    else
      error -> {:reply, error, nil}
    end
    Mutex.release(ExBanking.Lock, lock)
    result
  end
  
  def handle_call({:create_user, user}, _from, _state) do
    cond do
      ExBanking.Storage.user_exists?(user) -> {:reply, {:error, :user_already_exists}, nil}
      true -> ExBanking.Storage.save_user_to_storage({user, %{}, []})
        {:reply, :ok, nil}
    end
  end

  @doc """
  Transfer is essentially a combination of withdraw-deposit actions, but it requires locking of both users and more precise error handling
  """
  def handle_call({:transfer, from_user, to_user, amount, currency}, _from, _state) do
    lock = Mutex.await_all(ExBanking.Lock, [from_user, to_user])
    result = 
      cond do
        !ExBanking.Storage.user_exists?(from_user) -> {:error, :sender_does_not_exist}
        !ExBanking.Storage.user_exists?(to_user) -> {:error, :receiver_does_not_exist}
        true ->
          with {^from_user, from_balance, from_queue} <- ExBanking.Storage.get_user_from_storage(from_user),
               {^to_user, to_balance, to_queue}       <- ExBanking.Storage.get_user_from_storage(to_user) do
            cond do
              ExBanking.Helper.validate_queue(from_queue) != :ok -> {:error, :too_many_requests_to_sender}
              ExBanking.Helper.validate_queue(to_queue)   != :ok -> {:error, :too_many_requests_to_receiver}
              true ->
                with {:ok, new_from_balance} <- perform_action(from_user, from_balance, {:withdraw, amount, currency}, from_queue),
                     {:ok, new_to_balance}   <- perform_action(to_user, to_balance, {:deposit, amount, currency}, to_queue) do
                  {:ok, new_from_balance, new_to_balance}
                end
            end
          end
      end
    Mutex.release(ExBanking.Lock, lock)
    {:reply, result, nil}
  end

  @doc """
  When :process message is received for a user, worker knowns that something is very likely needs to be done for that user. 
  """
  def handle_info({:process, user}, _state) do
    case Mutex.lock(ExBanking.Lock, user) do
      {:error, _} -> send(self(), {:process, user})
      {:ok, lock} -> 
        case ExBanking.Storage.get_user_from_storage(user) do
          {^user, balance, [{action, from} | rest]} ->
            GenServer.reply(from, perform_action(user, balance, action, rest))
            unless rest == [], do: send(self(), {:process, user})
          error -> Logger.warn("Was going to process user #{user} but no actions was found: #{inspect(error)}")
        end
        Mutex.release(ExBanking.Lock, lock)
    end
    {:noreply, nil}
  end

  @doc """
  Worker starts assuming he has tons of work to do but he and his friends have lost all their messages. 
  Therefore he checks all the users with non-empty queues.
  """
  def handle_info(:init, _state) do
    ExBanking.Storage.get_users_with_pending_actions()
    |> Enum.map(fn user -> 
      user
      |> ExBanking.Router.choose_worker()
      |> via_tuple()
      |> GenServer.whereis()
      |> send({:process, user})
      end)
    {:noreply, nil}
  end

  @doc """
  Add action to the user's actions queue. 
  """
  def add_action(user, action) do
    user
    |> ExBanking.Router.choose_worker()
    |> via_tuple()
    |> GenServer.call({:add_action, user, action})
  end

  @doc """
  Create a user using this user's unique worker
  """
  def create_user(user) do
    user
    |> ExBanking.Router.choose_worker()
    |> via_tuple()
    |> GenServer.call({:create_user, user})
  end

  @doc """
  Transfer money using worker unique for this user pair
  """
  def transfer(from_user, to_user, amount, currency) do
    [from_user, to_user]
    |> Enum.sort()
    |> ExBanking.Router.choose_worker()
    |> via_tuple()
    |> GenServer.call({:transfer, from_user, to_user, amount, currency})
  end

  defp perform_action(user, balance, {:deposit, amount, currency}, rest_actions) do
    %{^currency => new_balance_value} = new_balance = Map.merge(balance, %{currency => amount}, fn _k, v1, v2 -> v1 + v2 end)
    ExBanking.Storage.save_user_to_storage({user, new_balance, rest_actions})
    {:ok, new_balance_value}
  end
  defp perform_action(user, balance, {:withdraw, amount, currency}, rest_actions) do
    with %{^currency => current_amount} when current_amount >= amount <- balance,
         new_balance <- current_amount - amount do
      ExBanking.Storage.save_user_to_storage({user, %{balance | currency => new_balance}, rest_actions})
      {:ok, new_balance}
    else
      _ -> ExBanking.Storage.save_user_to_storage({user, balance, rest_actions}) 
        {:error, :not_enough_money}
    end
  end
end