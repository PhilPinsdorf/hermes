defmodule Hermes.Directory do
  @moduledoc """
  The Directory context: the people calls can be forwarded to.
  """

  import Ecto.Query, warn: false
  alias Hermes.Repo

  alias Hermes.Directory.{Person, PhoneNumber}

  @topic "directory"

  @doc """
  Subscribes the caller to person changes (`{:person_changed, %Person{}}`).
  """
  def subscribe do
    Phoenix.PubSub.subscribe(Hermes.PubSub, @topic)
  end

  @doc """
  Returns all people, ordered by position, then name.

  With a `search` term only those whose name or number contains it are
  returned — the number as typed, so `0171` finds `+49171…`.
  """
  def list_people(search \\ nil) do
    Person
    |> search_people(search)
    |> order_by([p], asc: p.position, asc: p.name)
    |> Repo.all()
  end

  defp search_people(query, search) when search in [nil, ""], do: query

  defp search_people(query, search) do
    name = "%#{escape_like(String.trim(search))}%"

    case PhoneNumber.search_digits(search) do
      "" ->
        where(query, [p], ilike(p.name, ^name))

      digits ->
        where(query, [p], ilike(p.name, ^name) or like(p.phone_e164, ^"%#{digits}%"))
    end
  end

  # A name may well contain a % or _, which LIKE would read as a wildcard.
  defp escape_like(term) do
    String.replace(term, ~r/[\\%_]/, "\\\\\\0")
  end

  @doc """
  Gets a single person. Raises `Ecto.NoResultsError` if not found.
  """
  def get_person!(id), do: Repo.get!(Person, id)

  @doc """
  Creates a person. New people are appended at the end of the order unless a
  position is given.
  """
  def create_person(attrs) do
    attrs = Map.new(attrs, fn {k, v} -> {to_string(k), v} end)
    attrs = Map.put_new_lazy(attrs, "position", &next_position/0)

    %Person{}
    |> Person.changeset(attrs)
    |> Repo.insert()
    |> broadcast()
  end

  @doc """
  Updates a person.
  """
  def update_person(%Person{} = person, attrs) do
    person
    |> Person.changeset(attrs)
    |> Repo.update()
    |> broadcast()
  end

  @doc """
  Deletes a person.
  """
  def delete_person(%Person{} = person) do
    person
    |> Repo.delete()
    |> broadcast()
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking person changes.
  """
  def change_person(%Person{} = person, attrs \\ %{}) do
    Person.changeset(person, attrs)
  end

  defp next_position do
    (Repo.one(from p in Person, select: max(p.position)) || -1) + 1
  end

  defp broadcast({:ok, person} = result) do
    Phoenix.PubSub.broadcast(Hermes.PubSub, @topic, {:person_changed, person})
    result
  end

  defp broadcast(error), do: error
end
