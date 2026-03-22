defmodule TaniwhaWeb.UserSocketTest do
  use TaniwhaWeb.ChannelCase, async: true

  describe "connect/3" do
    setup do
      {:ok, token} = Taniwha.Auth.issue_token("test-api-key-for-tests")
      {:ok, token: token}
    end

    test "accepts connection with valid token and assigns current_user", %{token: token} do
      assert {:ok, socket} = connect(TaniwhaWeb.UserSocket, %{"token" => token})
      assert socket.assigns.current_user == "api_user"
    end

    test "rejects connection without token" do
      assert :error = connect(TaniwhaWeb.UserSocket, %{})
    end

    test "rejects connection with invalid token" do
      assert :error = connect(TaniwhaWeb.UserSocket, %{"token" => "invalid"})
    end
  end
end
