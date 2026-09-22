defmodule HermesWeb.Router do
  use HermesWeb, :router

  import HermesWeb.UserAuth
  import Phoenix.LiveDashboard.Router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {HermesWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_current_scope_for_user
    plug HermesWeb.Branding
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  # Unauthenticated liveness/readiness probe for Docker healthchecks.
  scope "/", HermesWeb do
    get "/healthz", HealthController, :show
  end

  # The logo appears on the login page too, so it is readable without a session.
  scope "/", HermesWeb do
    pipe_through :browser

    get "/branding/logo", BrandingController, :logo
  end

  # Other scopes may use custom stacks.
  # scope "/api", HermesWeb do
  #   pipe_through :api
  # end

  # Runtime metrics, processes, ETS and so on. Behind the login, since it
  # shows internals (see the authenticated scope below).

  ## Authentication routes

  scope "/", HermesWeb do
    pipe_through [:browser, :require_authenticated_user]

    live_session :require_authenticated_user,
      on_mount: [{HermesWeb.UserAuth, :require_authenticated}, HermesWeb.Branding] do
      live "/", DashboardLive, :index

      live "/schedule", ScheduleLive, :index
      live "/schedule/shifts/new", ScheduleLive, :new
      live "/schedule/shifts/:id/edit", ScheduleLive, :edit
      live "/schedule/overrides/new", ScheduleLive, :new_override

      live "/calls", CallLive.Index, :index

      live "/people", PersonLive.Index, :index
      live "/people/new", PersonLive.Form, :new
      live "/people/:id/edit", PersonLive.Form, :edit

      live "/settings", SettingsLive, :edit

      live "/users", UserLive.Index, :index
      live "/users/new", UserLive.Form, :new

      live "/users/settings", UserLive.Settings, :edit
    end

    # Its own live_session (they cannot be nested), but behind the same login.
    live_dashboard "/system",
      metrics: HermesWeb.Telemetry,
      on_mount: [{HermesWeb.UserAuth, :require_authenticated}]

    get "/settings/contact.vcf", ContactController, :show
    get "/settings/announcements/:name", AnnouncementController, :show
    post "/users/update-password", UserSessionController, :update_password
  end

  scope "/", HermesWeb do
    pipe_through [:browser]

    live_session :current_user,
      on_mount: [{HermesWeb.UserAuth, :mount_current_scope}, HermesWeb.Branding] do
      live "/users/log-in", UserLive.Login, :new
    end

    post "/users/log-in", UserSessionController, :create
    delete "/users/log-out", UserSessionController, :delete
  end
end
