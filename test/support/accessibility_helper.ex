defmodule TaniwhaWeb.AccessibilityHelper do
  @moduledoc """
  ARIA attribute assertion helpers for component tests.

  Uses LazyHTML (already in test deps) to parse rendered HTML and assert
  that accessibility requirements are met. Covers WCAG 2.2 AA basics.

  LazyHTML API notes:
  - `query(doc, selector)` returns a LazyHTML struct (Enumerable, one item per match)
  - `attribute(el, name)` returns a list of values (one per matched node)
  - `attributes(el)` returns a list of keyword lists (one per matched node)
  - `text(el)` returns the text content of all matched nodes concatenated
  """

  import ExUnit.Assertions

  @doc """
  Asserts that the HTML contains at least one valid `role="progressbar"` element
  with the required ARIA attributes: `aria-valuenow`, `aria-valuemin`, `aria-valuemax`.
  """
  @spec assert_aria_progressbar(String.t()) :: :ok
  def assert_aria_progressbar(html) do
    doc = LazyHTML.from_document(html)
    progressbars = LazyHTML.query(doc, "[role=progressbar]") |> Enum.to_list()

    assert progressbars != [],
           "Expected at least one element with role=\"progressbar\", got none.\nHTML: #{html}"

    Enum.each(progressbars, fn el ->
      valuenow = LazyHTML.attribute(el, "aria-valuenow")
      valuemin = LazyHTML.attribute(el, "aria-valuemin")
      valuemax = LazyHTML.attribute(el, "aria-valuemax")

      assert valuenow != [],
             "progressbar missing aria-valuenow.\nHTML: #{html}"

      assert valuemin != [],
             "progressbar missing aria-valuemin.\nHTML: #{html}"

      assert valuemax != [],
             "progressbar missing aria-valuemax.\nHTML: #{html}"
    end)

    :ok
  end

  @doc """
  Asserts that every `<button>` element in the HTML has either non-empty text
  content or an `aria-label` attribute. Returns `:ok` on success or raises on
  the first failing button.
  """
  @spec assert_labeled_buttons(String.t()) :: :ok
  def assert_labeled_buttons(html) do
    doc = LazyHTML.from_document(html)
    buttons = LazyHTML.query(doc, "button")

    Enum.each(buttons, fn el ->
      aria_labels = LazyHTML.attribute(el, "aria-label")
      text = el |> LazyHTML.text() |> String.trim()
      has_label = aria_labels != [] and hd(aria_labels) != ""
      has_text = text != ""

      assert has_label or has_text,
             "button has no accessible label (aria-label or text).\nButton HTML: #{LazyHTML.to_html(el)}"
    end)

    :ok
  end

  @doc """
  Asserts that no `<img>` element in the HTML is missing an `alt` attribute.

  Decorative images should use `alt=""` explicitly; this function only flags
  the complete absence of an `alt` attribute.
  """
  @spec assert_no_empty_alt(String.t()) :: :ok
  def assert_no_empty_alt(html) do
    doc = LazyHTML.from_document(html)
    images = LazyHTML.query(doc, "img")

    Enum.each(images, fn el ->
      alts = LazyHTML.attribute(el, "alt")

      assert alts != [],
             "img element is missing alt attribute.\nImage HTML: #{LazyHTML.to_html(el)}"
    end)

    :ok
  end
end
