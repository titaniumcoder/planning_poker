defmodule PlanningPoker.Poker.Poker do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "poker" do
    field :name, :string
    field :card_type, :string, default: "fibonacci"
    field :closed_at, :utc_datetime
    field :usernames, {:array, :string}, default: []

    has_many :votings, PlanningPoker.Poker.Voting, preload_order: [asc: :position]

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(poker, attrs) do
    poker
    |> cast(attrs, [:name, :card_type, :usernames])
    |> validate_required([:name])
    |> validate_inclusion(:card_type, ["fibonacci", "t-shirt"])
  end

  @doc "Changeset for closing/reopening a poker session"
  def close_changeset(poker, attrs) do
    poker
    |> cast(attrs, [:closed_at])
  end
end
