# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :hermes, :scopes,
  user: [
    default: true,
    module: Hermes.Accounts.Scope,
    assign_key: :current_scope,
    access_path: [:user, :id],
    schema_key: :user_id,
    schema_type: :id,
    schema_table: :users,
    test_data_fixture: Hermes.AccountsFixtures,
    test_setup_helper: :register_and_log_in_user
  ]

config :hermes,
  ecto_repos: [Hermes.Repo],
  generators: [timestamp_type: :utc_datetime]

# Configure the endpoint
config :hermes, HermesWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: HermesWeb.ErrorHTML, json: HermesWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Hermes.PubSub,
  live_view: [signing_salt: "K6Kwv5bd"]

# Configure the mailer
#
# By default it uses the "Local" adapter which stores the emails
# locally. You can see the emails in your browser, at "/dev/mailbox".
#
# For production it's recommended to configure a different adapter
# at the `config/runtime.exs`.
config :hermes, Hermes.Mailer, adapter: Swoosh.Adapters.Local

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.25.4",
  hermes: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.1.12",
  hermes: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("..", __DIR__)
  ]

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# The UI is German; this also translates Ecto's validation messages.
config :hermes, HermesWeb.Gettext, default_locale: "de"

# Shift schedules are defined in local time (Europe/Berlin), so we need a
# real time zone database for DST-aware conversions.
config :elixir, :time_zone_database, Tz.TimeZoneDatabase

# Time zone the weekly plan is interpreted in (overridable via HERMES_TIME_ZONE).
config :hermes, :time_zone, "Europe/Berlin"

# Asterisk REST Interface; credentials come from the environment (runtime.exs).
config :hermes, Hermes.Ari,
  base_url: "http://127.0.0.1:8088",
  username: "hermes",
  password: nil,
  app: "hermes",
  enabled: false

config :hermes, :ari_client, Hermes.Ari.Client.Http

# How long the called person has to press a key. The announcement alone runs
# about 7 seconds, so this must be noticeably longer.
config :hermes, :confirm_timeout_seconds, 20

# Announcements, in a volume shared with the Asterisk container.
config :hermes, :sounds_dir, "/var/lib/asterisk/sounds/hermes"

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
