defmodule ExBanking.Helper do
  @moduledoc """
  A small collection of helper functions
  """

  require Logger

  @doc """
  Only numbers with precision of 2 or less allowed. Any actual rounding would mean possible creating or loosing money.
  """
  @spec validate_amount(amount :: number) :: number | ExBanking.banking_error
  def validate_amount(amount) do
    rounded = Float.round(amount + 0.0, 2)
    if rounded == amount, do: {:ok, rounded}, else: {:error, :wrong_arguments}
  end

  @spec validate_queue(queue :: list) :: :ok | ExBanking.banking_error
  def validate_queue(queue) when length(queue) >= 10, do: {:error, :too_many_requests_to_user}
  def validate_queue(_), do: :ok
end