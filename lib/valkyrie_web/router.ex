defmodule ValkyrieWeb.Router do
  use ValkyrieWeb, :router

  use AshAuthentication.Phoenix.Router

  import AshAuthentication.Plug.Helpers

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {ValkyrieWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :load_from_session
  end

  pipeline :api do
    plug :accepts, ["json"]
    plug :load_from_bearer
    plug :set_actor, :user
  end

  scope "/", ValkyrieWeb do
    pipe_through :browser

    ash_authentication_live_session :authenticated_routes do
      # in each liveview, add one of the following at the top of the module:
      #
      # If an authenticated user must be present:
      # on_mount {ValkyrieWeb.LiveUserAuth, :live_user_required}
      #
      # If an authenticated user *may* be present:
      # on_mount {ValkyrieWeb.LiveUserAuth, :live_user_optional}
      #
      # If an authenticated user must *not* be present:
      # on_mount {ValkyrieWeb.LiveUserAuth, :live_no_user}
    end
  end

  scope "/", ValkyrieWeb do
    pipe_through :browser

    ash_authentication_live_session :authentication_required,
      on_mount:
        if(Application.compile_env(:valkyrie, :disable_auth, false),
          do: [{ValkyrieWeb.LiveUserAuth, :live_user_optional}],
          else: [{ValkyrieWeb.LiveUserAuth, :live_user_required}]
        ) do
      live "/", MemberLive.Index, :index
      live "/members", MemberLive.Index, :index
      live "/members/new", MemberLive.Form, :new
      live "/members/:id/edit", MemberLive.Form, :edit
    end

    auth_routes AuthController, Valkyrie.Accounts.User, path: "/auth"
    sign_out_route AuthController

    sign_in_route auth_routes_prefix: "/auth",
                  on_mount: [{ValkyrieWeb.LiveUserAuth, :live_no_user}],
                  overrides: [
                    ValkyrieWeb.AuthOverrides,
                    Elixir.AshAuthentication.Phoenix.Overrides.DaisyUI
                  ]
  end

  scope "/", ValkyrieWeb do
    # Public route, no authentication required - serves plain text
    get "/authorized_keys", AuthorizedKeysController, :authorized_keys
    get "/authorized_keys.sig", AuthorizedKeysController, :authorized_keys_signature
  end

  # Other scopes may use custom stacks.
  # scope "/api", ValkyrieWeb do
  #   pipe_through :api
  # end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:valkyrie, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: ValkyrieWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end

  if Application.compile_env(:valkyrie, :dev_routes) do
    import AshAdmin.Router

    scope "/admin" do
      pipe_through :browser

      ash_admin "/"
    end
  end
end
