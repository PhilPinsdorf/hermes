defmodule HermesWeb.Router do
  use HermesWeb, :router

  import HermesWeb.UserAuth

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {HermesWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_current_scope_for_user
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  # Unauthenticated liveness/readiness probe for Docker healthchecks.
  scope "/", HermesWeb do
    get "/healthz", HealthController, :show
  end

  # Other scopes may use custom stacks.
  # scope "/api", HermesWeb do
  #   pipe_through :api
  # end

  # Enable LiveDashboard in development
  if Application.compile_env(:hermes, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: HermesWeb.Telemetry
    end
  end

  ## Authentication routes

  scope "/", HermesWeb do
    pipe_through [:browser, :require_authenticated_user]

    live_session :require_authenticated_user,
      on_mount: [{HermesWeb.UserAuth, :require_authenticated}] do
      live "/", DashboardLive, :index

      live "/schedule", ScheduleLive, :index
      live "/schedule/shifts/new", ScheduleLive, :new
      live "/schedule/shifts/:id/edit", ScheduleLive, :edit
      live "/schedule/overrides", OverrideLive, :index

      live "/calls", CallLive.Index, :index

      live "/people", PersonLive.Index, :index
      live "/people/new", PersonLive.Form, :new
      live "/people/:id/edit", PersonLive.Form, :edit

      live "/settings", SettingsLive, :edit

      live "/users", UserLive.Index, :index
      live "/users/new", UserLive.Form, :new

      live "/users/settings", UserLive.Settings, :edit
    end

    get "/settings/contact.vcf", ContactController, :show
    get "/settings/announcements/:name", AnnouncementController, :show
    post "/users/update-password", UserSessionController, :update_password
  end

  scope "/", HermesWeb do
    pipe_through [:browser]

    live_session :current_user,
      on_mount: [{HermesWeb.UserAuth, :mount_current_scope}] do
      live "/users/log-in", UserLive.Login, :new
    end

    post "/users/log-in", UserSessionController, :create
    delete "/users/log-out", UserSessionController, :delete
  end
end
