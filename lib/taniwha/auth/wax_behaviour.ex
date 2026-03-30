defmodule Taniwha.Auth.WaxBehaviour do
  @moduledoc """
  Behaviour contract for the `wax_` WebAuthn library.

  Defines the two callbacks used by `Taniwha.Auth.WebAuthn` so that the
  cryptographic validation calls can be replaced with `Mox` mocks in tests.
  In production and development, `Application.get_env(:taniwha, :wax_module, Wax)`
  resolves to `Wax`, which satisfies this contract (duck-typed).
  """

  @doc "Validates a WebAuthn registration (attestation) response."
  @callback register(
              attestation_object_cbor :: binary(),
              client_data_json_raw :: binary(),
              challenge :: Wax.Challenge.t()
            ) :: {:ok, {Wax.AuthenticatorData.t(), term()}} | {:error, term()}

  @doc "Validates a WebAuthn authentication (assertion) response."
  @callback authenticate(
              credential_id :: binary(),
              auth_data_bin :: binary(),
              sig :: binary(),
              client_data_json_raw :: binary(),
              challenge :: Wax.Challenge.t(),
              credentials :: [{binary(), map()}]
            ) :: {:ok, Wax.AuthenticatorData.t()} | {:error, term()}
end
