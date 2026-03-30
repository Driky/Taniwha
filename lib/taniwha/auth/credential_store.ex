defmodule Taniwha.Auth.CredentialStore do
  @moduledoc """
  GenServer that stores encrypted user credentials on disk and keeps a
  live copy in memory for fast reads.

  ## Storage

  Credentials are serialised as JSON, encrypted with AES-256-GCM (see
  `Taniwha.Auth.Encryption`), and written atomically to a file at
  `<data_dir>/credentials.enc`.

  Writes use the write-to-temp-then-rename pattern so the live file is
  never partially written. A stale `.tmp` file (from a crash between write
  and rename) is ignored on startup and overwritten on the next successful
  write.

  ## Concurrency

  All mutations go through `GenServer.call/2` and are therefore serialised
  by the process mailbox — no explicit locking is required.

  ## Configuration

  | Env var              | Default          | Description                       |
  |----------------------|------------------|-----------------------------------|
  | `TANIWHA_DATA_DIR`   | `/data/taniwha`  | Directory for persistent data     |

  ## Key rotation warning

  The credential file is encrypted with a key derived from
  `SECRET_KEY_BASE`. **If `SECRET_KEY_BASE` is rotated**, the credential
  file becomes permanently unreadable. Delete `credentials.enc` and
  re-create all users after a key rotation. There is no automatic
  migration.

  ## Data model

  Users are stored as maps with the following keys:

      %{
        id:            String.t(),   # 32-char random hex
        username:      String.t(),
        password_hash: String.t(),   # bcrypt hash (log_rounds 12 in prod)
        role:          String.t(),   # "admin" | future: "readonly"
        passkeys:      list(),       # reserved for Task 8.3 WebAuthn
        created_at:    String.t(),   # ISO 8601
        updated_at:    String.t()    # ISO 8601
      }
  """

  use GenServer

  require Logger

  alias Taniwha.Auth.Encryption

  @type user_map() :: %{
          id: String.t(),
          username: String.t(),
          password_hash: String.t(),
          role: String.t(),
          passkeys: list(),
          created_at: String.t(),
          updated_at: String.t()
        }

  @type passkey_map() :: %{
          id: String.t(),
          credential_id: binary(),
          cose_key: binary(),
          sign_count: non_neg_integer(),
          label: String.t(),
          created_at: String.t()
        }

  @type state() :: %{
          data_dir: String.t(),
          secret_key_base: String.t(),
          users: [user_map()]
        }

  # ── Public API ────────────────────────────────────────────────────────────

  @doc """
  Starts the credential store.

  Pass `name: false` to skip global registration (useful in tests where
  the returned pid is used directly). Defaults to registering as
  `Taniwha.Auth.CredentialStore` when no `:name` option is given.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    {name, init_opts} = Keyword.pop(opts, :name, __MODULE__)
    gen_opts = if name, do: [name: name], else: []
    GenServer.start_link(__MODULE__, init_opts, gen_opts)
  end

  @doc """
  Creates a new user with the given `username` and `password`.

  Returns `{:ok, user_map()}` on success.
  Returns `{:error, :empty_username}` if `username` is blank.
  Returns `{:error, :username_taken}` if `username` already exists.
  """
  @spec create_user(String.t(), String.t(), GenServer.server()) ::
          {:ok, user_map()} | {:error, :username_taken | :empty_username}
  def create_user(username, password, server \\ __MODULE__) do
    GenServer.call(server, {:create_user, username, password})
  end

  @doc """
  Authenticates `username` against `password`.

  Uses `Bcrypt.no_user_verify/0` when the username is not found to prevent
  timing-based user enumeration.

  Returns `{:ok, user_map()}` on success, `{:error, :invalid_credentials}` otherwise.
  """
  @spec authenticate(String.t(), String.t(), GenServer.server()) ::
          {:ok, user_map()} | {:error, :invalid_credentials}
  def authenticate(username, password, server \\ __MODULE__) do
    GenServer.call(server, {:authenticate, username, password})
  end

  @doc "Returns `{:ok, user_map()}` for the given `id`, or `{:error, :not_found}`."
  @spec get_user(String.t(), GenServer.server()) ::
          {:ok, user_map()} | {:error, :not_found}
  def get_user(id, server \\ __MODULE__) do
    GenServer.call(server, {:get_user, id})
  end

  @doc "Returns `{:ok, user_map()}` for the given `username`, or `{:error, :not_found}`."
  @spec get_user_by_username(String.t(), GenServer.server()) ::
          {:ok, user_map()} | {:error, :not_found}
  def get_user_by_username(username, server \\ __MODULE__) do
    GenServer.call(server, {:get_user_by_username, username})
  end

  @doc """
  Replaces the password for the user with `id`.

  Returns `:ok` on success, `{:error, :not_found}` if the id does not exist.
  """
  @spec update_password(String.t(), String.t(), GenServer.server()) ::
          :ok | {:error, :not_found}
  def update_password(id, new_password, server \\ __MODULE__) do
    GenServer.call(server, {:update_password, id, new_password})
  end

  @doc "Removes the user with `id`. Returns `:ok` even if the id does not exist."
  @spec delete_user(String.t(), GenServer.server()) :: :ok
  def delete_user(id, server \\ __MODULE__) do
    GenServer.call(server, {:delete_user, id})
  end

  @doc "Returns `true` if at least one user exists."
  @spec has_any_users?(GenServer.server()) :: boolean()
  def has_any_users?(server \\ __MODULE__) do
    GenServer.call(server, :has_any_users?)
  end

  @doc "Returns all users without the `:password_hash` field."
  @spec list_users(GenServer.server()) :: [map()]
  def list_users(server \\ __MODULE__) do
    GenServer.call(server, :list_users)
  end

  @doc """
  Adds `passkey` to the passkeys list of the user with `user_id`.

  The passkey map must contain at least `:credential_id`, `:cose_key`,
  `:sign_count`, `:label`, and `:created_at`. A unique `:id` is generated
  automatically and prepended to the list (newest first).

  Returns `{:ok, updated_user}` or `{:error, :not_found}`.
  """
  @spec add_passkey(String.t(), map(), GenServer.server()) ::
          {:ok, user_map()} | {:error, :not_found}
  def add_passkey(user_id, passkey, server \\ __MODULE__) do
    GenServer.call(server, {:add_passkey, user_id, passkey})
  end

  @doc """
  Finds a passkey by its raw `credential_id` binary across all users.

  Returns `{:ok, {user_map(), passkey_map()}}` or `{:error, :not_found}`.
  """
  @spec get_passkey_by_credential_id(binary(), GenServer.server()) ::
          {:ok, {user_map(), passkey_map()}} | {:error, :not_found}
  def get_passkey_by_credential_id(credential_id, server \\ __MODULE__) do
    GenServer.call(server, {:get_passkey_by_credential_id, credential_id})
  end

  @doc """
  Updates the `sign_count` on the passkey identified by `passkey_id`
  within the user identified by `user_id`.

  Returns `:ok` or `{:error, :not_found}` when user or passkey is absent.
  """
  @spec update_passkey_sign_count(String.t(), String.t(), non_neg_integer(), GenServer.server()) ::
          :ok | {:error, :not_found}
  def update_passkey_sign_count(user_id, passkey_id, new_count, server \\ __MODULE__) do
    GenServer.call(server, {:update_passkey_sign_count, user_id, passkey_id, new_count})
  end

  @doc """
  Removes the passkey with `passkey_id` from the user's list.

  Returns `:ok` even if `passkey_id` is not found in the user's list (idempotent).
  Returns `{:error, :not_found}` if `user_id` does not exist.
  """
  @spec delete_passkey(String.t(), String.t(), GenServer.server()) ::
          :ok | {:error, :not_found}
  def delete_passkey(user_id, passkey_id, server \\ __MODULE__) do
    GenServer.call(server, {:delete_passkey, user_id, passkey_id})
  end

  # ── GenServer callbacks ───────────────────────────────────────────────────

  @impl true
  def init(opts) do
    data_dir =
      Keyword.get(opts, :data_dir, Application.get_env(:taniwha, :data_dir, "/data/taniwha"))

    secret_key_base =
      Keyword.get(
        opts,
        :secret_key_base,
        Application.fetch_env!(:taniwha, TaniwhaWeb.Endpoint)[:secret_key_base]
      )

    File.mkdir_p!(data_dir)

    state = %{data_dir: data_dir, secret_key_base: secret_key_base, users: []}
    {:ok, load_from_disk(state)}
  end

  @impl true
  def handle_call({:create_user, username, _password}, _from, state)
      when username == "" or is_nil(username) do
    {:reply, {:error, :empty_username}, state}
  end

  def handle_call({:create_user, username, password}, _from, state) do
    if Enum.any?(state.users, &(&1.username == username)) do
      {:reply, {:error, :username_taken}, state}
    else
      now = now_iso8601()

      user = %{
        id: generate_id(),
        username: username,
        password_hash: Bcrypt.hash_pwd_salt(password),
        role: "admin",
        passkeys: [],
        created_at: now,
        updated_at: now
      }

      new_state = %{state | users: [user | state.users]}
      persist(new_state)
      {:reply, {:ok, user}, new_state}
    end
  end

  def handle_call({:authenticate, username, password}, _from, state) do
    case Enum.find(state.users, &(&1.username == username)) do
      nil ->
        Bcrypt.no_user_verify()
        {:reply, {:error, :invalid_credentials}, state}

      user ->
        if Bcrypt.verify_pass(password, user.password_hash) do
          {:reply, {:ok, user}, state}
        else
          {:reply, {:error, :invalid_credentials}, state}
        end
    end
  end

  def handle_call({:get_user, id}, _from, state) do
    case Enum.find(state.users, &(&1.id == id)) do
      nil -> {:reply, {:error, :not_found}, state}
      user -> {:reply, {:ok, user}, state}
    end
  end

  def handle_call({:get_user_by_username, username}, _from, state) do
    case Enum.find(state.users, &(&1.username == username)) do
      nil -> {:reply, {:error, :not_found}, state}
      user -> {:reply, {:ok, user}, state}
    end
  end

  def handle_call({:update_password, id, new_password}, _from, state) do
    case Enum.find_index(state.users, &(&1.id == id)) do
      nil ->
        {:reply, {:error, :not_found}, state}

      index ->
        now = now_iso8601()

        updated =
          state.users
          |> Enum.at(index)
          |> Map.merge(%{password_hash: Bcrypt.hash_pwd_salt(new_password), updated_at: now})

        new_state = %{state | users: List.replace_at(state.users, index, updated)}
        persist(new_state)
        {:reply, :ok, new_state}
    end
  end

  def handle_call({:delete_user, id}, _from, state) do
    new_state = %{state | users: Enum.reject(state.users, &(&1.id == id))}
    persist(new_state)
    {:reply, :ok, new_state}
  end

  def handle_call(:has_any_users?, _from, state) do
    {:reply, state.users != [], state}
  end

  def handle_call(:list_users, _from, state) do
    sanitized = Enum.map(state.users, &Map.delete(&1, :password_hash))
    {:reply, sanitized, state}
  end

  def handle_call({:add_passkey, user_id, passkey}, _from, state) do
    passkey_with_id = Map.put(passkey, :id, generate_id())

    case update_in_list(state.users, &(&1.id == user_id), fn user ->
           %{user | passkeys: [passkey_with_id | user.passkeys]}
         end) do
      {:error, :not_found} ->
        {:reply, {:error, :not_found}, state}

      {:ok, updated_users, updated_user} ->
        new_state = %{state | users: updated_users}
        persist(new_state)
        {:reply, {:ok, updated_user}, new_state}
    end
  end

  def handle_call({:get_passkey_by_credential_id, credential_id}, _from, state) do
    result =
      Enum.find_value(state.users, fn user ->
        case Enum.find(user.passkeys, &(&1.credential_id == credential_id)) do
          nil -> nil
          pk -> {user, pk}
        end
      end)

    case result do
      nil -> {:reply, {:error, :not_found}, state}
      {user, pk} -> {:reply, {:ok, {user, pk}}, state}
    end
  end

  def handle_call({:update_passkey_sign_count, user_id, passkey_id, new_count}, _from, state) do
    case Enum.find_index(state.users, &(&1.id == user_id)) do
      nil ->
        {:reply, {:error, :not_found}, state}

      user_index ->
        user = Enum.at(state.users, user_index)

        case update_in_list(
               user.passkeys,
               &(&1.id == passkey_id),
               &Map.put(&1, :sign_count, new_count)
             ) do
          {:error, :not_found} ->
            {:reply, {:error, :not_found}, state}

          {:ok, updated_passkeys, _pk} ->
            updated_user = %{user | passkeys: updated_passkeys}
            new_state = %{state | users: List.replace_at(state.users, user_index, updated_user)}
            persist(new_state)
            {:reply, :ok, new_state}
        end
    end
  end

  def handle_call({:delete_passkey, user_id, passkey_id}, _from, state) do
    case update_in_list(state.users, &(&1.id == user_id), fn user ->
           %{user | passkeys: Enum.reject(user.passkeys, &(&1.id == passkey_id))}
         end) do
      {:error, :not_found} ->
        {:reply, {:error, :not_found}, state}

      {:ok, updated_users, _user} ->
        new_state = %{state | users: updated_users}
        persist(new_state)
        {:reply, :ok, new_state}
    end
  end

  # ── Private helpers ───────────────────────────────────────────────────────

  # Finds the first element matching `predicate`, applies `updater`, and returns
  # the updated list together with the updated element.
  @spec update_in_list([term()], (term() -> boolean()), (term() -> term())) ::
          {:ok, [term()], term()} | {:error, :not_found}
  defp update_in_list(list, predicate, updater) do
    case Enum.find_index(list, predicate) do
      nil ->
        {:error, :not_found}

      index ->
        updated = updater.(Enum.at(list, index))
        {:ok, List.replace_at(list, index, updated), updated}
    end
  end

  @spec persist(state()) :: :ok
  defp persist(state) do
    payload = Jason.encode!(%{version: 1, users: serialize_users(state.users)})
    encrypted = Encryption.encrypt(payload, state.secret_key_base)
    tmp = cred_file(state) <> ".tmp"
    File.write!(tmp, encrypted)
    File.rename!(tmp, cred_file(state))
    :ok
  end

  @spec serialize_users([user_map()]) :: [map()]
  defp serialize_users(users) do
    Enum.map(users, fn user ->
      %{user | passkeys: Enum.map(user.passkeys, &serialize_passkey/1)}
    end)
  end

  @spec serialize_passkey(passkey_map()) :: map()
  defp serialize_passkey(pk) do
    %{pk | credential_id: Base.encode64(pk.credential_id), cose_key: Base.encode64(pk.cose_key)}
  end

  @spec load_from_disk(state()) :: state()
  defp load_from_disk(state) do
    path = cred_file(state)

    if File.exists?(path) do
      encrypted = File.read!(path)

      case Encryption.decrypt(encrypted, state.secret_key_base) do
        {:ok, json} ->
          %{"users" => users} = Jason.decode!(json)
          %{state | users: Enum.map(users, &atomize_user/1)}

        {:error, :decryption_failed} ->
          Logger.error(
            "CredentialStore: failed to decrypt credentials file at #{path}. " <>
              "This may indicate a SECRET_KEY_BASE rotation. " <>
              "Starting with empty user store."
          )

          state
      end
    else
      state
    end
  end

  @spec cred_file(state()) :: String.t()
  defp cred_file(state), do: Path.join(state.data_dir, "credentials.enc")

  @spec atomize_user(map()) :: user_map()
  defp atomize_user(%{
         "id" => id,
         "username" => username,
         "password_hash" => password_hash,
         "role" => role,
         "passkeys" => passkeys,
         "created_at" => created_at,
         "updated_at" => updated_at
       }) do
    %{
      id: id,
      username: username,
      password_hash: password_hash,
      role: role,
      passkeys: Enum.map(passkeys || [], &atomize_passkey/1),
      created_at: created_at,
      updated_at: updated_at
    }
  end

  @spec atomize_passkey(map()) :: passkey_map()
  defp atomize_passkey(%{
         "id" => id,
         "credential_id" => cid_b64,
         "cose_key" => key_b64,
         "sign_count" => sign_count,
         "label" => label,
         "created_at" => created_at
       }) do
    %{
      id: id,
      credential_id: Base.decode64!(cid_b64),
      cose_key: Base.decode64!(key_b64),
      sign_count: sign_count,
      label: label,
      created_at: created_at
    }
  end

  @spec generate_id() :: String.t()
  defp generate_id do
    :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)
  end

  @spec now_iso8601() :: String.t()
  defp now_iso8601 do
    DateTime.utc_now() |> DateTime.to_iso8601()
  end
end
