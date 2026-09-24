defmodule PlanningPokerWeb.Forms.JoinPokerForm do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key false
  embedded_schema do
    field :name, :string
    field :privacy_agreement, :boolean, default: false
  end

  def changeset(form, attrs \\ %{}) do
    form
    |> cast(attrs, [:name, :privacy_agreement])
    |> validate_required([:name, :privacy_agreement])
    |> validate_length(:name, min: 1, max: 100)
    |> validate_acceptance(:privacy_agreement,
      message: "You must agree to the data privacy policy"
    )
  end
end
