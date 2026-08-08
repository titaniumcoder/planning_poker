defmodule PlanningPokerWeb.Forms.VotingForm do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key false
  embedded_schema do
    field :title, :string
    field :link, :string
    field :decision, :string
  end

  def changeset(form, attrs \\ %{}) do
    form
    |> cast(attrs, [:title, :link, :decision])
    |> validate_required([:title])
    |> validate_length(:title, min: 1, max: 200)
    |> validate_length(:link, max: 500)
    |> validate_length(:decision, max: 100)
    |> validate_url(:link)
  end

  defp validate_url(changeset, field) do
    validate_change(changeset, field, &validate_url_format/2)
  end

  defp validate_url_format(field, value) do
    if valid_url?(value) do
      []
    else
      [{field, "must be a valid URL"}]
    end
  end

  defp valid_url?(nil), do: true
  defp valid_url?(""), do: true

  defp valid_url?(url) when is_binary(url) do
    uri = URI.parse(url)
    uri.scheme in ["http", "https"] and is_binary(uri.host) and uri.host != ""
  end

  defp valid_url?(_), do: false
end
