defmodule Monitorex.ExportsTest do
  use ExUnit.Case, async: true

  alias Monitorex.Exports

  defmodule SampleStruct do
    defstruct [:value]
  end

  describe "to_csv/2" do
    test "generates CSV with header and rows" do
      data = [%{name: "Alice", age: 30}, %{name: "Bob", age: 25}]
      csv = Exports.to_csv(data, [:name, :age])

      assert csv == "name,age\nAlice,30\nBob,25"
    end

    test "escapes commas in cells" do
      csv = Exports.to_csv([%{note: "Hello, world"}], [:note])
      assert csv == ~s{note\n"Hello, world"}
    end

    test "escapes quotes in cells" do
      csv = Exports.to_csv([%{note: ~s{Say "hi"}}], [:note])
      assert csv == ~s{note\n"Say ""hi\"""}
    end

    test "escapes newlines in cells" do
      csv = Exports.to_csv([%{note: "line1\nline2"}], [:note])
      assert csv == ~s{note\n"line1\nline2"}
    end

    test "handles nil values as empty" do
      csv = Exports.to_csv([%{name: nil}], [:name])
      assert csv == "name\n"
    end

    test "handles numbers and atoms" do
      csv = Exports.to_csv([%{status: :ok, count: 42}], [:status, :count])
      assert csv == "status,count\nok,42"
    end

    test "uses default empty string for missing fields" do
      csv = Exports.to_csv([%{name: "Alice"}], [:name, :missing])
      assert csv == "name,missing\nAlice,"
    end
  end

  describe "to_json/2" do
    test "encodes data as pretty JSON" do
      data = [%{name: "Alice", age: 30}]
      json = Exports.to_json(data, [:name, :age])

      assert Jason.decode!(json) == [%{"name" => "Alice", "age" => 30}]
    end

    test "converts structs to maps" do
      data = [%SampleStruct{value: 1}]
      json = Exports.to_json(data)

      assert Jason.decode!(json) == [%{"value" => 1}]
    end

    test "filters fields when provided" do
      data = [%{a: 1, b: 2}]
      json = Exports.to_json(data, [:a])

      assert Jason.decode!(json) == [%{"a" => 1}]
    end
  end

  describe "sanitize_filename/1" do
    test "lowercases and replaces special characters" do
      assert Exports.sanitize_filename("Host Detail!") == "host_detail"
    end

    test "preserves dots, dashes, and underscores" do
      assert Exports.sanitize_filename("page_v1.2-test") == "page_v1.2-test"
    end

    test "collapses multiple underscores" do
      assert Exports.sanitize_filename("a  b") == "a_b"
    end

    test "trims leading and trailing underscores" do
      assert Exports.sanitize_filename("!page!") == "page"
    end
  end

  describe "filename/2" do
    test "builds timestamped filename" do
      name = Exports.filename("outbound overview", "csv")

      assert String.starts_with?(name, "monitorex_outbound_overview_")
      assert String.ends_with?(name, ".csv")
      refute String.contains?(name, ":")
    end
  end
end
