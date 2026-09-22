defmodule HermesWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use HermesWeb, :html

  # Embed all files in layouts/* within this module.
  # The default root.html.heex file contains the HTML
  # skeleton of your application, namely HTML headers
  # and other static content.
  embed_templates "layouts/*"

  @doc """
  Renders your app layout.

  This function is typically invoked from every template,
  and it often contains your application menu, sidebar,
  or similar.

  ## Examples

      <Layouts.app flash={@flash}>
        <h1>Content</h1>
      </Layouts.app>

  """
  attr :flash, :map, required: true, doc: "the map of flash messages"

  attr :current_scope, :map,
    default: nil,
    doc: "the current [scope](https://hexdocs.pm/phoenix/scopes.html)"

  attr :wide, :boolean, default: false, doc: "use the full width, e.g. for the weekly grid"

  attr :branding, :map,
    default: nil,
    doc: "name, accent and logo of this installation (see Hermes.Branding)"

  attr :current_path, :string, default: nil, doc: "marks the current page in the navigation"

  slot :inner_block, required: true

  def app(assigns) do
    # Pages inside a live_session get this from the on_mount hook; anything
    # else falls back to reading the settings.
    assigns =
      assigns
      |> assign(:branding, assigns.branding || Hermes.Branding.summary())
      |> assign(:active_path, active_path(assigns.current_path))

    ~H"""
    <header class="border-b border-base-300 bg-base-100">
      <div class="mx-auto flex h-14 max-w-6xl items-center gap-3 px-4 sm:gap-4 sm:px-6">
        <.link navigate={~p"/"} class="flex items-center gap-2.5 shrink-0">
          <.brand_mark branding={@branding} />
          <span class="font-semibold tracking-tight">{@branding.name}</span>
        </.link>

        <nav :if={@current_scope && @current_scope.user} class="hidden md:flex items-center gap-0.5">
          <.nav_link :for={{path, label} <- nav_items()} path={path} active_path={@active_path}>
            {label}
          </.nav_link>
        </nav>

        <div class="ml-auto flex items-center gap-1">
          <.link
            :if={@current_scope && @current_scope.user}
            navigate={~p"/users/settings"}
            class="hidden lg:inline-flex btn btn-ghost btn-sm font-normal text-base-content/70"
          >
            {@current_scope.user.email}
          </.link>
          <.link
            :if={@current_scope && @current_scope.user}
            href={~p"/users/log-out"}
            method="delete"
            class="btn btn-ghost btn-sm"
          >
            Abmelden
          </.link>
          <.theme_toggle />
        </div>
      </div>

      <nav
        :if={@current_scope && @current_scope.user}
        id="mobile-nav"
        phx-hook=".NavScroll"
        class="md:hidden flex gap-1 overflow-x-auto border-t border-base-300 px-3 py-1.5 [scrollbar-width:none]"
      >
        <.nav_link :for={{path, label} <- nav_items()} path={path} active_path={@active_path}>
          {label}
        </.nav_link>
        <.nav_link path={elem(account_item(), 0)} active_path={@active_path}>
          {elem(account_item(), 1)}
        </.nav_link>
      </nav>
    </header>

    <main class="px-4 py-6 sm:px-6 sm:py-8">
      <div class={["mx-auto space-y-6", (@wide && "max-w-6xl") || "max-w-3xl"]}>
        {render_slot(@inner_block)}
      </div>
    </main>

    <.flash_group flash={@flash} />

    <%!-- The scrollable navigation starts at the left again on every page
          change; without this the entry one is on can end up out of sight. --%>
    <script :type={Phoenix.LiveView.ColocatedHook} name=".NavScroll">
      export default {
        mounted() { this.showCurrent() },
        updated() { this.showCurrent() },
        showCurrent() {
          const current = this.el.querySelector('[aria-current="page"]')
          if (!current) return
          const centered = current.offsetLeft - (this.el.clientWidth - current.offsetWidth) / 2
          this.el.scrollLeft = Math.max(0, centered)
        }
      }
    </script>
    """
  end

  defp nav_items do
    [
      {"/", "Übersicht"},
      {"/schedule", "Wochenplan"},
      {"/calls", "Anrufe"},
      {"/people", "Personen"},
      {"/settings", "Einstellungen"},
      {"/users", "Benutzer"}
    ]
  end

  attr :path, :string, required: true
  attr :active_path, :string, default: nil
  slot :inner_block, required: true

  defp nav_link(assigns) do
    ~H"""
    <.link
      navigate={@path}
      class={[
        "nav-link whitespace-nowrap rounded-md px-3 text-sm text-base-content/70",
        "flex items-center min-h-10 md:min-h-9 hover:bg-base-200"
      ]}
      aria-current={@path == @active_path && "page"}
    >
      {render_slot(@inner_block)}
    </.link>
    """
  end

  # The account page lives under /users/…, but belongs to "Konto", not to
  # "Benutzer". The longest matching entry therefore wins.
  defp account_item, do: {"/users/settings", "Konto"}

  defp active_path(nil), do: nil

  defp active_path(current) do
    [account_item() | nav_items()]
    |> Enum.map(&elem(&1, 0))
    |> Enum.filter(&matches?(&1, current))
    |> Enum.max_by(&String.length/1, fn -> nil end)
  end

  # "/" only matches exactly; everything else also matches its subpages.
  defp matches?("/", current), do: current == "/"
  defp matches?(path, current), do: current == path or String.starts_with?(current, path <> "/")

  @doc """
  Appearance of this installation for the root layout, which is also rendered
  for pages that never went through a LiveView.
  """
  def brand(assigns) do
    assigns[:branding] || Hermes.Branding.summary()
  end

  @doc """
  The accent as a `<style>` element for the page head.

  HEEx does not interpolate inside `<style>`, so the element is built as raw
  HTML. Its content comes from a fixed set of colours (`Hermes.Branding`),
  never from user input.
  """
  def accent_style(assigns) do
    Phoenix.HTML.raw("<style>" <> brand(assigns).accent_css <> "</style>")
  end

  @doc """
  The logo of this installation, or a neutral icon when none was uploaded.
  """
  attr :branding, :map, required: true
  attr :class, :string, default: "size-7"

  def brand_mark(assigns) do
    ~H"""
    <img
      :if={@branding.logo?}
      src={~p"/branding/logo?v=#{@branding.logo_version}"}
      alt=""
      class={[@class, "object-contain"]}
    />
    <span
      :if={!@branding.logo?}
      class={[@class, "flex items-center justify-center rounded bg-primary text-primary-content"]}
    >
      <.icon name="hero-phone-arrow-up-right" class="size-4" />
    </span>
    """
  end

  @doc """
  Shows the flash group with standard titles and content.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        title={gettext("We can't find the internet")}
        phx-disconnected={show(".phx-client-error #client-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title={gettext("Something went wrong!")}
        phx-disconnected={show(".phx-server-error #server-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end

  @doc """
  Provides dark vs light theme toggle based on themes defined in app.css.

  See <head> in root.html.heex which applies the theme before page load.
  """
  def theme_toggle(assigns) do
    ~H"""
    <div class="card relative flex flex-row items-center border-2 border-base-300 bg-base-300 rounded-full">
      <div class="absolute w-1/3 h-full rounded-full border-1 border-base-200 bg-base-100 brightness-200 left-0 [[data-theme=light]_&]:left-1/3 [[data-theme=dark]_&]:left-2/3 transition-[left]" />

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="system"
      >
        <.icon name="hero-computer-desktop-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="light"
      >
        <.icon name="hero-sun-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="dark"
      >
        <.icon name="hero-moon-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>
    </div>
    """
  end
end
