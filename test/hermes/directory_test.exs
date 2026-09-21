defmodule Hermes.DirectoryTest do
  use Hermes.DataCase, async: true

  alias Hermes.Directory
  alias Hermes.Directory.Person

  import Hermes.DirectoryFixtures

  describe "create_person/1" do
    test "stores the phone number normalized to E.164" do
      assert {:ok, %Person{} = person} =
               Directory.create_person(%{name: "Anna", phone_e164: "0171 1234567"})

      assert person.phone_e164 == "+491711234567"
      assert person.active
      assert person.ring_timeout_seconds == nil
    end

    test "requires name and phone number" do
      assert {:error, changeset} = Directory.create_person(%{})
      assert %{name: ["can't be blank"], phone_e164: ["can't be blank"]} = errors_on(changeset)
    end

    test "rejects an invalid phone number with a readable message" do
      assert {:error, changeset} = Directory.create_person(%{name: "Anna", phone_e164: "123"})
      assert ["braucht eine Vorwahl" <> _] = errors_on(changeset).phone_e164
    end

    test "rejects the same number twice, regardless of how it was typed" do
      person_fixture(phone_e164: "0171 1234567")

      assert {:error, changeset} =
               Directory.create_person(%{name: "Bert", phone_e164: "+49 171 123 45 67"})

      assert ["ist bereits einer anderen Person zugeordnet"] = errors_on(changeset).phone_e164
    end

    test "validates the ring timeout range" do
      assert {:error, changeset} =
               Directory.create_person(valid_person_attributes(ring_timeout_seconds: 2))

      assert errors_on(changeset).ring_timeout_seconds != []
    end

    test "appends new people at the end of the order" do
      a = person_fixture()
      b = person_fixture()
      assert b.position == a.position + 1
    end

    test "broadcasts the change" do
      Directory.subscribe()
      person = person_fixture()
      assert_receive {:person_changed, ^person}
    end
  end

  describe "internal extensions" do
    test "a person may be an extension of the Fritz!Box" do
      assert {:ok, person} = Directory.create_person(%{name: "Büro", phone_e164: "**621"})
      assert person.phone_e164 == "**621"
    end
  end

  describe "list_people/0" do
    test "orders by position, then name" do
      c = person_fixture(name: "Carla", position: 0)
      a = person_fixture(name: "Anna", position: 1)
      b = person_fixture(name: "Bert", position: 1)

      assert Enum.map(Directory.list_people(), & &1.id) == [c.id, a.id, b.id]
    end
  end

  describe "update_person/2" do
    test "normalizes a changed phone number" do
      person = person_fixture()
      assert {:ok, person} = Directory.update_person(person, %{phone_e164: "030 123456"})
      assert person.phone_e164 == "+4930123456"
    end

    test "can deactivate a person" do
      person = person_fixture()
      assert {:ok, %Person{active: false}} = Directory.update_person(person, %{active: false})
    end
  end

  describe "delete_person/1" do
    test "deletes the person" do
      person = person_fixture()
      assert {:ok, %Person{}} = Directory.delete_person(person)
      assert_raise Ecto.NoResultsError, fn -> Directory.get_person!(person.id) end
    end
  end
end
