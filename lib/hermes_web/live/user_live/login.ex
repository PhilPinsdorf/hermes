defmodule HermesWeb.UserLive.Login do
  use HermesWeb, :live_view

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={@current_scope}
      branding={@branding}
      current_path={@current_path}
    >
      <div class="mx-auto max-w-sm space-y-6 pt-6">
        <div class="flex flex-col items-center gap-3 text-center">
          <Layouts.brand_mark branding={@branding} class="size-12" />
          <div>
            <h1 class="text-xl font-semibold tracking-tight">{@branding.name}</h1>
            <p class="text-sm text-base-content/70">
              {if @current_scope,
                do: "Für diese Aktion musst du dich erneut anmelden.",
                else: "Bereitschaft und Weiterleitung verwalten"}
            </p>
          </div>
        </div>

        <.form
          :let={f}
          for={@form}
          id="login_form_password"
          class="card card-body"
          action={~p"/users/log-in"}
          phx-submit="submit_password"
          phx-trigger-action={@trigger_submit}
        >
          <.input
            readonly={!!@current_scope}
            field={f[:email]}
            type="email"
            label="E-Mail"
            autocomplete="username"
            spellcheck="false"
            required
            phx-mounted={JS.focus()}
          />
          <.input
            field={@form[:password]}
            type="password"
            label="Passwort"
            autocomplete="current-password"
            spellcheck="false"
            required
          />
          <.button class="btn btn-primary w-full" name={@form[:remember_me].name} value="true">
            Anmelden und angemeldet bleiben <span aria-hidden="true">→</span>
          </.button>
          <.button class="btn btn-primary btn-soft w-full mt-2">
            Nur dieses Mal anmelden
          </.button>
        </.form>

        <p class="text-sm text-base-content/70 text-center">
          Passwort vergessen? Bitte wende dich an den Betreiber dieser Installation.
        </p>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    email =
      Phoenix.Flash.get(socket.assigns.flash, :email) ||
        get_in(socket.assigns, [:current_scope, Access.key(:user), Access.key(:email)])

    form = to_form(%{"email" => email}, as: "user")

    {:ok, assign(socket, form: form, trigger_submit: false, page_title: "Anmelden")}
  end

  @impl true
  def handle_event("submit_password", _params, socket) do
    {:noreply, assign(socket, :trigger_submit, true)}
  end
end
