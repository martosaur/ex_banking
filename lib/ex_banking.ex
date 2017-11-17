defmodule ExBanking do
  @moduledoc """
  The module provides core interface for the banking operations
  """

  @type banking_error :: {:error,
    :wrong_arguments                |
    :user_already_exists            |
    :user_does_not_exist            |
    :not_enough_money               |
    :sender_does_not_exist          |
    :receiver_does_not_exist        |
    :too_many_requests_to_user      |
    :too_many_requests_to_sender    |
    :too_many_requests_to_receiver
  }
  
  @doc """
  Creates a new user
  """
  @spec create_user(user :: String.t) :: :ok | banking_error
  def create_user(user) when is_binary(user) do
    ExBanking.Worker.create_user(user)
  end
  def create_user(_), do: {:error, :wrong_arguments}

  @doc """
  Deposit money to user's account 
  """
  @spec deposit(user :: String.t, amount :: number, currency :: String.t) :: {:ok, new_balance :: number} | banking_error
  def deposit(user, amount, currency) when is_binary(user) and is_binary(currency) and amount >= 0 do 
    with {:ok, clean_amount} <- ExBanking.Helper.validate_amount(amount) do
      add_action(user, {:deposit, clean_amount, currency})
    end
  end
  def deposit(_, _, _), do: {:error, :wrong_arguments}

  @doc """
  Withdraw money from user' account
  """
  @spec withdraw(user :: String.t, amount :: number, currency :: String.t) :: {:ok, new_balance :: number} | banking_error
  def withdraw(user, amount, currency) when is_binary(user) and is_binary(currency) and amount >= 0 do
    with {:ok, clean_amount} <- ExBanking.Helper.validate_amount(amount) do
      add_action(user, {:withdraw, clean_amount, currency})
    end
  end
  def withdraw(_, _, _), do: {:error, :wrong_arguments}

  @doc """
  Returns current user's balance for given currency
  """
  @spec get_balance(user :: String.t, currency :: String.t) :: {:ok, balance :: number} | banking_error
  def get_balance(user, currency) when is_binary(user) and is_binary(currency) do
    case ExBanking.Storage.get_user_from_storage(user) do
      {_, %{^currency => balance}, _queue} -> {:ok, balance}
      {^user, _balance, _queue} -> {:ok, 0.0}
      error -> error
    end
  end
  def get_balance(_, _), do: {:error, :wrong_arguments}

  @doc """
  Sends money from one user to another
  """
  @spec send(from_user :: String.t, to_user :: String.t, amount :: number, currency :: String.t) :: {:ok, from_user_balance :: number, to_user_balance :: number} | banking_error
  def send(user, user, _, _), do: {:error, :wrong_arguments}
  def send(from_user, to_user, amount, currency) when is_binary(from_user) and is_binary(to_user) and is_binary(currency) and amount > 0 do
    with {:ok, clean_amount} <- ExBanking.Helper.validate_amount(amount) do
      ExBanking.Worker.transfer(from_user, to_user, clean_amount, currency)
    end
  end
  def send(_, _, _, _), do: {:error, :wrong_arguments}

  @spec add_action(user :: String.t, action :: {:deposit, amount :: number, currency :: String.t} | {:withdraw, amount :: number,  currency :: String.t}) :: {:ok, balance :: number} | banking_error
  defp add_action(user, action) do
    case ExBanking.Worker.add_action(user, action) do
      :ok -> receive do
          {_, response} -> response
        end
      error -> error
    end
  end
end
