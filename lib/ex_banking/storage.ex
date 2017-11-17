defmodule ExBanking.Storage do
  @moduledoc """
  Module responsible for all ETS interactions
  """

  require Logger
  
  @type user_data :: {user ::String.t, balance :: map, queue :: list}

  def create_table do
    :ets.new(:storage, [:set, :public, :named_table])
  end

  @spec get_user_from_storage(user :: String.t) :: user_data | ExBanking.banking_error
  def get_user_from_storage(user) do
    case :ets.lookup(:storage, user) do
      [user] -> user
      [] -> {:error, :user_does_not_exist}
      r -> Logger.error("Couldn't get user from storage: #{inspect(r)}")
    end
  end

  @spec get_users_with_pending_actions() :: [user :: String.t]
  def get_users_with_pending_actions do
    :ets.match(:storage, {:"$1", :"_", :"_"}) -- :ets.match(:storage, {:"$1", :"_", []})
    |> List.flatten
  end

  @spec user_exists?(user :: String.t) :: true | false
  def user_exists?(user) do
    if :ets.lookup(:storage, user) == [], do: false, else: true
  end

  @spec save_user_to_storage(user_data :: user_data) :: true
  def save_user_to_storage(user_data) do
    :ets.insert(:storage, user_data)
  end
end