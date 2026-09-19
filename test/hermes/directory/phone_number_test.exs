defmodule Hermes.Directory.PhoneNumberTest do
  use ExUnit.Case, async: true

  alias Hermes.Directory.PhoneNumber

  doctest PhoneNumber, import: true

  describe "normalize/1 accepts" do
    for {input, expected} <- [
          # national mobile, with the usual separators
          {"01711234567", "+491711234567"},
          {"0171 1234567", "+491711234567"},
          {"0171-123 45 67", "+491711234567"},
          {"0171/1234567", "+491711234567"},
          {"(0171) 1234567", "+491711234567"},
          {"0171.123.4567", "+491711234567"},
          {"  0171 1234567  ", "+491711234567"},
          # national landline
          {"030 1234567", "+49301234567"},
          {"030/12 34 56-78", "+493012345678"},
          # international, already E.164
          {"+491711234567", "+491711234567"},
          {"+49 171 1234567", "+491711234567"},
          # "+49 (0)" notation
          {"+49 (0) 171 1234567", "+491711234567"},
          {"+49(0)171 1234567", "+491711234567"},
          {"+49 ( 0 ) 30 123456", "+4930123456"},
          # trunk zero wrongly kept after the country code
          {"+49 0171 1234567", "+491711234567"},
          {"0049 0171 1234567", "+491711234567"},
          # 00 international prefix
          {"0049 171 1234567", "+491711234567"},
          {"0043 664 1234567", "+436641234567"},
          # foreign numbers stay untouched
          {"+43 664 1234567", "+436641234567"},
          {"+41 79 123 45 67", "+41791234567"}
        ] do
      test "#{inspect(input)} -> #{expected}" do
        assert PhoneNumber.normalize(unquote(input)) == {:ok, unquote(expected)}
      end
    end
  end

  describe "normalize/1 rejects" do
    test "nil and blank input" do
      assert PhoneNumber.normalize(nil) == {:error, :blank}
      assert PhoneNumber.normalize("") == {:error, :blank}
      assert PhoneNumber.normalize("  - / ") == {:error, :blank}
    end

    test "letters and other characters" do
      assert PhoneNumber.normalize("0171 CALLME") == {:error, :invalid_characters}
      assert PhoneNumber.normalize("0171#123") == {:error, :invalid_characters}
      assert PhoneNumber.normalize("0171 1234567 ext. 5") == {:error, :invalid_characters}
    end

    test "a plus sign that is not at the start" do
      assert PhoneNumber.normalize("0171+1234567") == {:error, :invalid_characters}
    end

    test "local numbers without area code" do
      assert PhoneNumber.normalize("1234567") == {:error, :missing_prefix}
    end

    test "numbers that are too short or too long for E.164" do
      assert PhoneNumber.normalize("0171") == {:error, :invalid}
      assert PhoneNumber.normalize("+49 171 1234567 8901234") == {:error, :invalid}
    end

    test "country code starting with 0" do
      assert PhoneNumber.normalize("+0171234567") == {:error, :invalid}
    end
  end

  describe "error_message/1" do
    test "has a German message for every error reason" do
      for reason <- [:blank, :invalid_characters, :missing_prefix, :invalid] do
        assert is_binary(PhoneNumber.error_message(reason))
      end
    end
  end

  describe "validate_change/2" do
    import Ecto.Changeset

    defp changeset(value) do
      cast({%{}, %{phone: :string}}, %{phone: value}, [:phone])
    end

    test "replaces the change with the E.164 form" do
      assert get_change(PhoneNumber.validate_change(changeset("0171 1234567"), :phone), :phone) ==
               "+491711234567"
    end

    test "adds a readable error" do
      cs = PhoneNumber.validate_change(changeset("1234567"), :phone)
      refute cs.valid?
      assert {"braucht eine Vorwahl" <> _, []} = cs.errors[:phone]
    end

    test "leaves a changeset without change alone" do
      cs = changeset(nil)
      assert PhoneNumber.validate_change(cs, :phone) == cs
    end
  end

  describe "format/1" do
    test "splits off the German country code" do
      assert PhoneNumber.format("+491711234567") == "+49 1711234567"
    end

    test "leaves other numbers and nil readable" do
      assert PhoneNumber.format("+436641234567") == "+436641234567"
      assert PhoneNumber.format(nil) == ""
    end
  end
end
