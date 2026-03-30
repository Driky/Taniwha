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

  # ── Private helpers ───────────────────────────────────────────────────────

  @spec persist(state()) :: :ok
  defp persist(state) do
    payload = Jason.encode!(%{version: 1, users: state.users})
    encrypted = Encryption.encrypt(payload, state.secret_key_base)
    tmp = cred_file(state) <> ".tmp"
    File.write!(tmp, encrypted)
    File.rename!(tmp, cred_file(state))
    :ok
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
      passkeys: passkeys || [],
      created_at: created_at,
      updated_at: updated_at
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
