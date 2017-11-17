defmodule ExBankingTest do
  use ExUnit.Case, async: true
  doctest ExBanking

  test "create user: positive" do
    assert ExBanking.create_user("user1") == :ok
    assert :ets.lookup(:storage, "user1") == [{"user1", %{}, []}]
  end

  test "create_user: cannot create two identical users" do
    :ets.insert(:storage, {"user2", %{}, []})
    assert ExBanking.create_user("user2") == {:error, :user_already_exists}
  end

  test "create_user: arguments validation" do
    assert ExBanking.create_user(123) == {:error, :wrong_arguments}
  end

  test "deposit: deposit in different currencies" do
    :ets.insert(:storage, {"user3", %{}, []})
    assert ExBanking.deposit("user3", 10.0, "EUR") == {:ok, 10.0}
    assert ExBanking.deposit("user3", 10, "EUR") == {:ok, 20.0}
    assert ExBanking.deposit("user3", 15.0, "eur") == {:ok, 15.0}
    assert :ets.lookup(:storage, "user3") == [{"user3", %{"EUR" => 20.0, "eur" => 15.0}, []}]
  end

  test "deposit: unknown user" do
    assert ExBanking.deposit("some_user", 1, "EUR") == {:error, :user_does_not_exist}
  end

  test "deposit: arguments validation" do
    assert ExBanking.deposit(123, 10.0, "EUR") == {:error, :wrong_arguments}
    assert ExBanking.deposit("123", -1, "EUR") == {:error, :wrong_arguments}
    assert ExBanking.deposit("123", 10.9999, "EUR") == {:error, :wrong_arguments}
    assert ExBanking.deposit("123", 10, :EUR) == {:error, :wrong_arguments}
  end

  test "get_balance: positive" do
    :ets.insert(:storage, {"user4", %{"EUR" => 11.0}, []})
    assert ExBanking.get_balance("user4", "EUR") == {:ok, 11.0}
    assert ExBanking.get_balance("user4", "USD") == {:ok, 0}
  end
    
  test "get_balance: unknown user" do
    assert ExBanking.get_balance("some_user", "EUR") == {:error, :user_does_not_exist}
  end

  test "get_balance: arguments validation" do
    assert ExBanking.get_balance(:hello, "EUR") == {:error, :wrong_arguments}
    assert ExBanking.get_balance("hello", 1234) == {:error, :wrong_arguments}
  end

  test "withdraw: positive" do
    :ets.insert(:storage, {"user5", %{"EUR" => 5.21}, []})
    assert ExBanking.withdraw("user5", 0.21, "EUR") == {:ok, 5.0}
    assert ExBanking.withdraw("user5", 1, "EUR") == {:ok, 4.0}
    assert :ets.lookup(:storage, "user5") == [{"user5", %{"EUR" => 4.0}, []}]
  end

  test "withdraw: unknown user" do
    assert ExBanking.withdraw("some_user", 9.99, "EUR") == {:error, :user_does_not_exist}
  end

  test "withdraw: not enough money" do
    :ets.insert(:storage, {"user6", %{"PLN" => 100.0}, []})
    assert ExBanking.withdraw("user6", 500, "PLN") == {:error, :not_enough_money}
  end

  test "withdraw: arguments validation" do
    assert ExBanking.withdraw([], 10.0, "EUR") == {:error, :wrong_arguments}
    assert ExBanking.withdraw("[]", -987.000, "EUR") == {:error, :wrong_arguments}
    assert ExBanking.withdraw("[]", 987.98765678, "EUR") == {:error, :wrong_arguments}
    assert ExBanking.withdraw("[]", 987, [{}]) == {:error, :wrong_arguments}
  end

  test "full queue" do
    :ets.insert(:storage, {"user7", %{"EUR" => 10.0}, Enum.to_list(1..10)})
    assert ExBanking.get_balance("user7", "EUR") == {:ok, 10.0}
    assert ExBanking.deposit("user7", 12, "USD") == {:error, :too_many_requests_to_user}
    assert ExBanking.withdraw("user7", 12, "PLN") == {:error, :too_many_requests_to_user}
  end

  test "send: positive" do
    :ets.insert(:storage, {"userA1", %{"EUR" => 10.0}, []})
    :ets.insert(:storage, {"userB1", %{}, []})
    assert ExBanking.send("userA1", "userB1", 10.0, "EUR") == {:ok, 0, 10.0}
    assert :ets.lookup(:storage, "userA1") == [{"userA1", %{"EUR" => 0.0}, []}]
    assert :ets.lookup(:storage, "userB1") == [{"userB1", %{"EUR" => 10.0}, []}]
  end

  test "send: send zero" do
    # don't mess with the bank
    assert ExBanking.send("user_zero1", "user_zero2", 0, "EUR") == {:error, :wrong_arguments}
  end

  test "send: not enough money" do
    :ets.insert(:storage, {"userA2", %{"EUR" => 10.0}, []})
    :ets.insert(:storage, {"userB2", %{}, []})
    assert ExBanking.send("userA2", "userB2", 15.0, "EUR") == {:error, :not_enough_money}
    assert :ets.lookup(:storage, "userA2") == [{"userA2", %{"EUR" => 10.0}, []}]
    assert :ets.lookup(:storage, "userB2") == [{"userB2", %{}, []}]
  end                              
  
  test "send: sender does not exist" do
    :ets.insert(:storage, {"userB3", %{}, []})
    assert ExBanking.send("userA3", "userB3", 15.0, "EUR") == {:error, :sender_does_not_exist}
  end
  
  test "send: receiver does not exist" do
    :ets.insert(:storage, {"userA4", %{"EUR" => 20.0}, []})
    assert ExBanking.send("userA4", "userB4", 15.0, "EUR") == {:error, :receiver_does_not_exist}
  end

  test "send: too many requests to sender" do
    :ets.insert(:storage, {"userA5", %{"EUR" => 10.0}, Enum.to_list(1..10)})
    :ets.insert(:storage, {"userB5", %{}, []})
    assert ExBanking.send("userA5", "userB5", 15.0, "EUR") == {:error, :too_many_requests_to_sender}
  end
  
  test "send: too many requests to receiver" do
    :ets.insert(:storage, {"userA6", %{"EUR" => 10.0}, []})
    :ets.insert(:storage, {"userB6", %{}, Enum.to_list(1..10)})
    assert ExBanking.send("userA6", "userB6", 10.0, "EUR") == {:error, :too_many_requests_to_receiver}
  end

  test "send: send to himself" do
    :ets.insert(:storage, {"userA7", %{"EUR" => 10.0}, []})
    assert ExBanking.send("userA7", "userA7", 10.0, "EUR") == {:error, :wrong_arguments}
  end

  test "send: arguments validation" do
    assert ExBanking.send(1, "1", 10.0, "EUR") == {:error, :wrong_arguments}
    assert ExBanking.send("1", 1, 10.0, "EUR") == {:error, :wrong_arguments}
    assert ExBanking.send("1", "2", -10.0, "EUR") == {:error, :wrong_arguments}
    assert ExBanking.send("1", "2", 10.123123, "EUR") == {:error, :wrong_arguments}
    assert ExBanking.send("1", "2", 10, 0.0) == {:error, :wrong_arguments}
  end

  test "complex test" do
    ExBanking.create_user("Siri")
    ExBanking.create_user("Keeton")
    assert ExBanking.deposit("Siri", 10.0, "EUR") == {:ok, 10.0}
    assert ExBanking.send("Siri", "Keeton", 4.0, "EUR") == {:ok, 6.0, 4.0}
    assert ExBanking.get_balance("Siri", "EUR") == {:ok, 6.0}
    assert ExBanking.withdraw("Keeton", 3.0, "EUR") == {:ok, 1.0}
    assert ExBanking.deposit("Keeton", 99.99, "USD") == {:ok, 99.99}
    assert ExBanking.send("Keeton", "Siri", 99.99, "EUR") == {:error, :not_enough_money}
    assert :ets.lookup(:storage, "Siri") == [{"Siri", %{"EUR" => 6.0}, []}]
    assert :ets.lookup(:storage, "Keeton") == [{"Keeton", %{"EUR" => 1.0, "USD" => 99.99}, []}]
  end
end
