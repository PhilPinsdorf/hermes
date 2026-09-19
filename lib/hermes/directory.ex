defmodule Hermes.Directory do
  @moduledoc """
  The Directory context: the people calls can be forwarded to.
  """

  import Ecto.Query, warn: false
  alias Hermes.Repo

  alias Hermes.Directory.Person

  @topic "directory"

  @doc """
  Subscribes the caller to person changes (`{:person_changed, %Person{}}`).
  """
  def subscribe do
    Phoenix.PubSub.subscribe(Hermes.PubSub, @topic)
  end

  @doc """
  Returns all people, ordered by position, then name.
  """
  def list_people do
    Repo.all(from p in Person, order_by: [asc: p.position, asc: p.name])
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
