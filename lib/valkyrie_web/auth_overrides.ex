defmodule ValkyrieWeb.AuthOverrides do
  use AshAuthentication.Phoenix.Overrides
  alias AshAuthentication.Phoenix.Components

  # For a complete reference, see https://hexdocs.pm/ash_authentication_phoenix/ui-overrides.html

  override Components.Banner do
    set :image_url, "/images/logo.svg"
    set :dark_image_url, "/images/logo.svg"
    set :href_url, "/"
  end

  override Components.OAuth2 do
    # Drop the generic OIDC provider icon so the button text stays centered.
    set :icon_class, "hidden"
    # `w-full` forces the button to span its column (btn-block alone hugs the
    # text here), so it centers under the logo instead of left-aligning.
    set :link_class, "btn w-full"
  end
end
