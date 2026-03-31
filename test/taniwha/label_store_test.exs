defmodule Taniwha.LabelStoreTest do
  use ExUnit.Case, async: true

  alias Taniwha.LabelStore

  setup do
    tmp_dir = Path.join(System.tmp_dir!(), "taniwha_ls_#{:erlang.unique_integer([:positive])}")
    on_exit(fn -> File.rm_rf!(tmp_dir) end)

    store = start_supervised!({LabelStore, data_dir: tmp_dir, name: false})

    {:ok, store: store, tmp_dir: tmp_dir}
  end

  # ── Batch B1: auto_assign/2 — auto-colour from palette ───────────────────

  describe "auto_assign/2" do
    test "returns a colour triplet for an unknown label", %{store: store} do
      {dot, bg, text} = LabelStore.auto_assign("Movies", store)
      assert is_binary(dot) and String.starts_with?(dot, "#")
      assert is_binary(bg) and String.starts_with?(bg, "#")
      assert is_binary(text) and String.starts_with?(text, "#")
    end

    test "same label always returns the same colours on repeated calls", %{store: store} do
      first = LabelStore.auto_assign("Movies", store)
      second = LabelStore.auto_assign("Movies", store)
      assert first == second
    end

    test "different labels get different dot colours when palette not exhausted", %{store: store} do
      {dot1, _, _} = LabelStore.auto_assign("Movies", store)
      {dot2, _, _} = LabelStore.auto_assign("Linux", store)
      assert dot1 != dot2
    end

    test "auto-assigns from the 6-colour palette in order", %{store: store} do
      labels = ["A", "B", "C", "D", "E", "F"]
      colours = Enum.map(labels, fn l -> LabelStore.auto_assign(l, store) |> elem(0) end)

      palette = LabelStore.palette_dot_colours()
      assert colours == palette
    end

    test "wraps around after palette is exhausted", %{store: store} do
      # Exhaust the palette with 6 labels
      Enum.each(1..6, fn i -> LabelStore.auto_assign("label#{i}", store) end)

      # 7th label wraps to palette[0]
      {dot7, _, _} = LabelStore.auto_assign("label7", store)
      {dot1, _, _} = LabelStore.auto_assign("label1", store)
      assert dot7 == dot1
    end
  end

  # ── Batch B2: set_color/4 — explicit colour override ─────────────────────

  describe "set_color/4" do
    test "stores a custom colour triplet", %{store: store} do
      :ok = LabelStore.set_color("Movies", "#ff0000", "#ffe0e0", "#cc0000", store)
      assert LabelStore.auto_assign("Movies", store) == {"#ff0000", "#ffe0e0", "#cc0000"}
    end

    test "overrides a previously auto-assigned colour", %{store: store} do
      LabelStore.auto_assign("Movies", store)
      :ok = LabelStore.set_color("Movies", "#ff0000", "#ffe0e0", "#cc0000", store)
      assert LabelStore.auto_assign("Movies", store) == {"#ff0000", "#ffe0e0", "#cc0000"}
    end
  end

  # ── Batch B3: delete/2 ────────────────────────────────────────────────────

  describe "delete/2" do
    test "removes an existing label entry", %{store: store} do
      LabelStore.auto_assign("Movies", store)
      :ok = LabelStore.delete("Movies", store)
      all = LabelStore.get_all(store)
      refute Map.has_key?(all, "Movies")
    end

    test "is a no-op for a label that does not exist", %{store: store} do
      assert :ok = LabelStore.delete("NonExistent", store)
    end
  end

  # ── Batch B4: get_all/1 ───────────────────────────────────────────────────

  describe "get_all/1" do
    test "returns empty map when no labels stored", %{store: store} do
      assert LabelStore.get_all(store) == %{}
    end

    test "returns map of all stored labels with their colour triplets", %{store: store} do
      LabelStore.auto_assign("Movies", store)
      LabelStore.auto_assign("Linux", store)
      all = LabelStore.get_all(store)
      assert map_size(all) == 2
      assert Map.has_key?(all, "Movies")
      assert Map.has_key?(all, "Linux")
    end
  end

  # ── Batch B5: persistence across restarts ────────────────────────────────

  describe "file persistence" do
    test "persists labels to labels.json in data_dir", %{store: store, tmp_dir: tmp_dir} do
      LabelStore.auto_assign("Movies", store)
      assert File.exists?(Path.join(tmp_dir, "labels.json"))
    end

    test "reloads stored labels on restart", %{store: store, tmp_dir: tmp_dir} do
      {dot, bg, text} = LabelStore.auto_assign("Movies", store)

      # Start a new store pointing at the same dir
      new_store = start_supervised!({LabelStore, data_dir: tmp_dir, name: false}, id: :new_store)

      assert LabelStore.auto_assign("Movies", new_store) == {dot, bg, text}
    end

    test "previously auto-assigned indices are preserved so new labels get fresh colours",
         %{store: store, tmp_dir: tmp_dir} do
      # Assign label with first palette colour
      {dot1, _, _} = LabelStore.auto_assign("Movies", store)

      # Restart
      new_store =
        start_supervised!({LabelStore, data_dir: tmp_dir, name: false}, id: :new_store2)

      # New label should get the SECOND palette colour, not the first
      {dot2, _, _} = LabelStore.auto_assign("Linux", new_store)
      assert dot2 != dot1
    end
  end
end
