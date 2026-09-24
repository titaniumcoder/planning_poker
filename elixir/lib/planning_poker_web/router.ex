defmodule PlanningPokerWeb.Router do
  use PlanningPokerWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {PlanningPokerWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", PlanningPokerWeb do
    pipe_through :browser

    live "/", HomeLive
    live "/poker", CreatePokerLive

    # Session-based poker routes
    get "/poker/:id", PokerController, :join
    post "/poker/:id", PokerController, :identify_user
    get "/poker/:id/leave", PokerController, :leave
    get "/poker/:id/creator/:username/:token", PokerController, :join_creator

    live_session :authenticated_poker,
      on_mount: [{PlanningPokerWeb.PokerAuth, :ensure_authenticated}] do
      live "/poker/:id/live", PokerLive
    end

    live "/privacy", PrivacyLive
  end

  # Other scopes may use custom stacks.
  # scope "/api", PlanningPokerWeb do
  #   pipe_through :api
  # end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:planning_poker, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: PlanningPokerWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
