defmodule ValkyrieWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use ValkyrieWeb, :html

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

  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <.navbar id="navbar" rounded="large" padding="large" class="sticky">
      <:list icon="hero-user-group">
        <.link navigate="/members" title="Members">
          Members
        </.link>
      </:list>
      <:list icon="hero-shield-exclamation">
        <.link navigate="/members/audit">
          Audit Log
        </.link>
      </:list>
    </.navbar>
    <main class="px-4 py-20 sm:px-6 lg:px-8">
      <div class="mx-auto w-full space-y-4">
        {render_slot(@inner_block)}
      </div>
    </main>

    <ValkyrieWeb.Components.Alert.flash_group position="top_left" flash={@flash} />
    """
  end
end
