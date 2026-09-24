defmodule PlanningPoker.Poker.Voting do
  use Ecto.Schema
  import Ecto.Changeset

  schema "votings" do
    field :title, :string
    field :link, :string
    field :decision, :string
    field :votes, {:array, :map}, default: []
    field :position, :integer

    belongs_to :poker, PlanningPoker.Poker.Poker, type: :binary_id

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(voting, attrs) do
    voting
    |> cast(attrs, [:title, :link, :decision, :votes, :position, :poker_id])
    |> validate_required([:title, :position, :poker_id])
    |> validate_length(:decision, max: 100)
    |> foreign_key_constraint(:poker_id)
  end
end
