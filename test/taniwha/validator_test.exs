defmodule Taniwha.ValidatorTest do
  @moduledoc false
  use ExUnit.Case, async: true

  alias Taniwha.Validator

  # ---------------------------------------------------------------------------
  # validate_hash/1
  # ---------------------------------------------------------------------------

  describe "validate_hash/1" do
    test "accepts a valid 40-char lowercase hex string" do
      assert :ok = Validator.validate_hash(String.duplicate("a", 40))
    end

    test "accepts a valid 40-char uppercase hex string" do
      assert :ok = Validator.validate_hash(String.duplicate("A", 40))
    end

    test "accepts a mixed-case hex string" do
      assert :ok = Validator.validate_hash("aAbBcCdDeEfF00112233445566778899aAbBcCdD")
    end

    test "rejects a string shorter than 40 chars" do
      assert {:error, :invalid_hash} = Validator.validate_hash("abc123")
    end

    test "rejects a string longer than 40 chars" do
      assert {:error, :invalid_hash} = Validator.validate_hash(String.duplicate("a", 41))
    end

    test "rejects a 40-char string with non-hex characters" do
      assert {:error, :invalid_hash} = Validator.validate_hash(String.duplicate("g", 40))
    end

    test "rejects a non-binary value" do
      assert {:error, :invalid_hash} = Validator.validate_hash(12_345)
    end

    test "rejects nil" do
      assert {:error, :invalid_hash} = Validator.validate_hash(nil)
    end
  end

  # ---------------------------------------------------------------------------
  # validate_priority/1
  # ---------------------------------------------------------------------------

  describe "validate_priority/1" do
    test "accepts 0" do
      assert :ok = Validator.validate_priority(0)
    end

    test "accepts 1" do
      assert :ok = Validator.validate_priority(1)
    end

    test "accepts 2" do
      assert :ok = Validator.validate_priority(2)
    end

    test "rejects 3" do
      assert {:error, :invalid_priority} = Validator.validate_priority(3)
    end

    test "rejects -1" do
      assert {:error, :invalid_priority} = Validator.validate_priority(-1)
    end

    test "rejects a string representation" do
      assert {:error, :invalid_priority} = Validator.validate_priority("1")
    end

    test "rejects nil" do
      assert {:error, :invalid_priority} = Validator.validate_priority(nil)
    end
  end

  # ---------------------------------------------------------------------------
  # validate_url/1
  # ---------------------------------------------------------------------------

  describe "validate_url/1" do
    test "accepts a magnet link" do
      assert :ok =
               Validator.validate_url(
                 "magnet:?xt=urn:btih:dd8255ecdc7ca55fb0bbf81323d87062db1f6d1c"
               )
    end

    test "accepts an http URL" do
      assert :ok = Validator.validate_url("http://example.com/file.torrent")
    end

    test "accepts an https URL" do
      assert :ok = Validator.validate_url("https://example.com/file.torrent")
    end

    test "rejects an ftp URL" do
      assert {:error, :invalid_url} = Validator.validate_url("ftp://example.com/file.torrent")
    end

    test "rejects an empty string" do
      assert {:error, :invalid_url} = Validator.validate_url("")
    end

    test "rejects plain text" do
      assert {:error, :invalid_url} = Validator.validate_url("not a url at all")
    end

    test "rejects a schemeless URL" do
      assert {:error, :invalid_url} = Validator.validate_url("example.com/file.torrent")
    end

    test "rejects a non-binary value" do
      assert {:error, :invalid_url} = Validator.validate_url(nil)
    end
  end
end
