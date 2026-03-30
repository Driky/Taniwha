defmodule Taniwha.Auth.CredentialStoreTest do
  use ExUnit.Case, async: true

  alias Taniwha.Auth.CredentialStore

  @secret "test_secret_key_base_for_credential_store_testing_at_least_64_chars"

  setup do
    tmp_dir = Path.join(System.tmp_dir!(), "taniwha_cs_#{:erlang.unique_integer([:positive])}")
    on_exit(fn -> File.rm_rf!(tmp_dir) end)

    # name: false avoids registering under a global atom, which would
    # conflict when tests run concurrently (async: true).
    store =
      start_supervised!(
        {CredentialStore, data_dir: tmp_dir, secret_key_base: @secret, name: false}
      )

    {:ok, store: store, tmp_dir: tmp_dir}
  end

  # ── Batch B1: create_user + authenticate happy path ───────────────────────

  describe "create_user/3 and authenticate/3 — happy path" do
    test "creates a user and authenticates with correct password", %{store: store} do
      assert {:ok, user} = CredentialStore.create_user("alice", "password123", store)
      assert user.username == "alice"
      assert user.role == "admin"
      assert is_binary(user.id) and byte_size(user.id) > 0
      assert is_binary(user.password_hash)
      assert is_binary(user.created_at)
      assert is_binary(user.updated_at)
      assert user.passkeys == []

      assert {:ok, ^user} = CredentialStore.authenticate("alice", "password123", store)
    end
  end

  # ── Batch B2: authenticate failures ──────────────────────────────────────

  describe "authenticate/3 — failures" do
    test "wrong password returns {:error, :invalid_credentials}", %{store: store} do
      CredentialStore.create_user("bob", "correct_password", store)

      assert {:error, :invalid_credentials} =
               CredentialStore.authenticate("bob", "wrong_password", store)
    end

    test "non-existent username returns {:error, :invalid_credentials}", %{store: store} do
      assert {:error, :invalid_credentials} =
               CredentialStore.authenticate("nobody", "password", store)
    end
  end

  # ── Batch B3: create_user validation ─────────────────────────────────────

  describe "create_user/3 — validation" do
    test "empty username returns {:error, :empty_username}", %{store: store} do
      assert {:error, :empty_username} = CredentialStore.create_user("", "password", store)
    end

    test "duplicate username returns {:error, :username_taken}", %{store: store} do
      assert {:ok, _} = CredentialStore.create_user("alice", "pass1", store)
      assert {:error, :username_taken} = CredentialStore.create_user("alice", "pass2", store)
    end
  end

  # ── Batch B4: has_any_users? and list_users ───────────────────────────────

  describe "has_any_users?/1" do
    test "returns false when store is empty", %{store: store} do
      refute CredentialStore.has_any_users?(store)
    end

    test "returns true after creating a user", %{store: store} do
      CredentialStore.create_user("alice", "pass", store)
      assert CredentialStore.has_any_users?(store)
    end
  end

  describe "list_users/1" do
    test "returns empty list when store is empty", %{store: store} do
      assert CredentialStore.list_users(store) == []
    end

    test "does not include :password_hash", %{store: store} do
      CredentialStore.create_user("alice", "pass", store)
      [user] = CredentialStore.list_users(store)
      refute Map.has_key?(user, :password_hash)
      assert user.username == "alice"
    end

    test "includes all other user fields", %{store: store} do
      CredentialStore.create_user("alice", "pass", store)
      [user] = CredentialStore.list_users(store)
      assert Map.has_key?(user, :id)
      assert Map.has_key?(user, :username)
      assert Map.has_key?(user, :role)
      assert Map.has_key?(user, :passkeys)
      assert Map.has_key?(user, :created_at)
      assert Map.has_key?(user, :updated_at)
    end
  end

  # ── Batch B5: get_user / get_user_by_username ─────────────────────────────

  describe "get_user/2" do
    test "returns the user by id", %{store: store} do
      {:ok, user} = CredentialStore.create_user("alice", "pass", store)
      assert {:ok, ^user} = CredentialStore.get_user(user.id, store)
    end

    test "returns {:error, :not_found} for unknown id", %{store: store} do
      assert {:error, :not_found} = CredentialStore.get_user("nonexistent_id", store)
    end
  end

  describe "get_user_by_username/2" do
    test "returns the user by username", %{store: store} do
      {:ok, user} = CredentialStore.create_user("alice", "pass", store)
      assert {:ok, ^user} = CredentialStore.get_user_by_username("alice", store)
    end

    test "returns {:error, :not_found} for unknown username", %{store: store} do
      assert {:error, :not_found} = CredentialStore.get_user_by_username("nobody", store)
    end
  end

  # ── Batch B6: update_password ─────────────────────────────────────────────

  describe "update_password/3" do
    test "old password no longer works after update", %{store: store} do
      {:ok, user} = CredentialStore.create_user("alice", "old_pass", store)
      assert :ok = CredentialStore.update_password(user.id, "new_pass", store)

      assert {:error, :invalid_credentials} =
               CredentialStore.authenticate("alice", "old_pass", store)
    end

    test "new password authenticates successfully after update", %{store: store} do
      {:ok, user} = CredentialStore.create_user("alice", "old_pass", store)
      CredentialStore.update_password(user.id, "new_pass", store)

      assert {:ok, _} = CredentialStore.authenticate("alice", "new_pass", store)
    end

    test "returns {:error, :not_found} for unknown id", %{store: store} do
      assert {:error, :not_found} = CredentialStore.update_password("bad_id", "pass", store)
    end
  end

  # ── Batch B7: delete_user ─────────────────────────────────────────────────

  describe "delete_user/2" do
    test "removes the user from the store", %{store: store} do
      {:ok, user} = CredentialStore.create_user("alice", "pass", store)
      assert :ok = CredentialStore.delete_user(user.id, store)
      assert {:error, :not_found} = CredentialStore.get_user(user.id, store)
    end

    test "is :ok for an unknown id (idempotent)", %{store: store} do
      assert :ok = CredentialStore.delete_user("nonexistent_id", store)
    end
  end

  # ── Batch B8: file persistence ────────────────────────────────────────────

  describe "file persistence" do
    test "user survives a GenServer restart with the same data_dir", %{
      store: store,
      tmp_dir: tmp_dir
    } do
      {:ok, user} = CredentialStore.create_user("alice", "pass", store)

      # Stop via the child spec id so ExUnit removes the child cleanly.
      :ok = stop_supervised(CredentialStore)

      # Start a fresh GenServer pointing at the same data directory
      new_store =
        start_supervised!(
          {CredentialStore, data_dir: tmp_dir, secret_key_base: @secret, name: false},
          id: :restarted_store
        )

      assert {:ok, reloaded} = CredentialStore.get_user(user.id, new_store)
      assert reloaded.username == "alice"
      assert reloaded.id == user.id
    end

    test "authentication still works after restart", %{store: store, tmp_dir: tmp_dir} do
      CredentialStore.create_user("alice", "pass", store)
      :ok = stop_supervised(CredentialStore)

      new_store =
        start_supervised!(
          {CredentialStore, data_dir: tmp_dir, secret_key_base: @secret, name: false},
          id: :restarted_store_auth
        )

      assert {:ok, _} = CredentialStore.authenticate("alice", "pass", new_store)
    end
  end

  # ── Batch B9: atomic write ────────────────────────────────────────────────

  describe "atomic write" do
    test "no .tmp file remains after a successful write", %{store: store, tmp_dir: tmp_dir} do
      CredentialStore.create_user("alice", "pass", store)

      refute File.exists?(Path.join(tmp_dir, "credentials.enc.tmp"))
      assert File.exists?(Path.join(tmp_dir, "credentials.enc"))
    end

    test "credentials file is created after the first write", %{store: store, tmp_dir: tmp_dir} do
      refute File.exists?(Path.join(tmp_dir, "credentials.enc"))
      CredentialStore.create_user("alice", "pass", store)
      assert File.exists?(Path.join(tmp_dir, "credentials.enc"))
    end
  end
end
