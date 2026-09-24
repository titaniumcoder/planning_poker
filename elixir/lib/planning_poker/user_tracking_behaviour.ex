defmodule PlanningPoker.UserTrackingBehaviour do
  @moduledoc """
  Behaviour for user tracking functionality.
  """

  @doc """
  Starts user tracking for a poker session.
  """
  @callback start_user_tracking(poker_id :: String.t()) :: :ok | {:error, term()}

  @doc """
  Stops user tracking for a poker session.
  """
  @callback stop_user_tracking(poker_id :: String.t()) :: :ok | {:error, term()}

  @doc """
  Joins a user to the tracking server.
  """
  @callback join_user(poker_id :: String.t(), username :: String.t()) ::
              {:ok, token :: String.t()} | {:error, term()}

  @doc """
  Marks a user as online in the tracking server.
  """
  @callback mark_user_online(poker_id :: String.t(), username :: String.t(), pid :: pid()) ::
              {:ok, map()} | {:error, term()}

  @doc """
  Marks a user as offline in the tracking server.
  """
  @callback mark_user_offline(poker_id :: String.t(), username :: String.t(), pid :: pid()) ::
              {:ok, map()} | {:error, term()}

  @doc """
  Toggles user mute status.
  """
  @callback toggle_mute_user(poker_id :: String.t(), username :: String.t()) ::
              {:ok, map()} | {:error, term()}

  @doc """
  Gets all users for a poker session.
  """
  @callback get_users(poker_id :: String.t()) :: [map()] | {:error, term()}

  @doc """
  Gets online users for a poker session.
  """
  @callback get_online_users(poker_id :: String.t()) :: [map()] | {:error, term()}

  @doc """
  Gets unmuted online users for a poker session.
  """
  @callback get_unmuted_online_users(poker_id :: String.t()) :: [String.t()] | {:error, term()}

  @doc """
  Validates if a username is available for a poker session.
  """
  @callback username_available?(poker_id :: String.t(), username :: String.t()) ::
              boolean() | {:error, term()}
end
