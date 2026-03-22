defmodule Taniwha.AuthTest do
  use ExUnit.Case, async: true

  alias Taniwha.Auth

  describe "issue_token/1" do
    test "returns {:ok, jwt} with correct API key" do
      assert {:ok, token} = Auth.issue_token("test-api-key-for-tests")
      assert is_binary(token)
    end

    test "returns {:error, :invalid_api_key} with wrong API key" do
      assert {:error, :invalid_api_key} = Auth.issue_token("wrong-key")
    end

    test "returns {:error, :invalid_api_key} with nil API key" do
      assert {:error, :invalid_api_key} = Auth.issue_token(nil)
    end
  end

  describe "verify_token/1" do
    setup do
      {:ok, token} = Auth.issue_token("test-api-key-for-tests")
      {:ok, token: token}
    end

    test "returns {:ok, subject} with valid JWT", %{token: token} do
      assert {:ok, "api_user"} = Auth.verify_token(token)
    end

    test "returns {:error, _} with expired JWT" do
      # Override exp to Unix timestamp 1 (Jan 1 1970) — guaranteed past
      {:ok, expired_token, _claims} = Auth.encode_and_sign("api_user", %{"exp" => 1}, [])
      assert {:error, _} = Auth.verify_token(expired_token)
    end

    test "returns {:error, _} with tampered JWT", %{token: token} do
      assert {:error, _} = Auth.verify_token(token <> "tampered")
    end

    test "returns {:error, _} with garbage input" do
      assert {:error, _} = Auth.verify_token("not-a-jwt")
    end
  end
end
