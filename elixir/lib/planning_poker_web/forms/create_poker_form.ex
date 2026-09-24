defmodule PlanningPokerWeb.Forms.CreatePokerForm do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key false
  embedded_schema do
    field :name, :string
    field :card_type, :string, default: "fibonacci"
    field :username, :string
    field :privacy_agreement, :boolean, default: false
  end

  def changeset(form, attrs \\ %{}) do
    form
    |> cast(attrs, [:name, :card_type, :username, :privacy_agreement])
    |> validate_required([:name, :username])
    |> validate_length(:name, min: 1, max: 100)
    |> validate_length(:username, min: 1, max: 100)
    |> validate_inclusion(:card_type, ["fibonacci", "t-shirt"])
    |> validate_acceptance(:privacy_agreement)
  end
end
