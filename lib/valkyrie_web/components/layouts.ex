defmodule ValkyrieWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use ValkyrieWeb, :html

  import ValkyrieWeb.Components.UserIndicator

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

  attr :current_user, :map,
    default: nil,
    doc: "the signed-in user, used to show admin-only navigation"

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
      <:list :if={@current_user && @current_user.is_admin} icon="hero-key">
        <.link navigate="/doors" title="Doors">
          Doors
        </.link>
      </:list>
      <:end_content>
        <.user_indicator current_user={@current_user} />
      </:end_content>
    </.navbar>
    <main class="px-4 py-20 sm:px-6 lg:px-8">
      <div class="mx-auto w-full space-y-4">
        {render_slot(@inner_block)}
      </div>
    </main>

    <.version_footer version={Valkyrie.version()} />

    <ValkyrieWeb.Components.Alert.flash_group position="top_right" flash={@flash} />
    """
  end

  @repo_url "https://github.com/xHain-hackspace/valkyrie"

  attr :version, :string, required: true

  defp version_footer(assigns) do
    assigns = assign(assigns, :href, version_url(assigns.version))

    ~H"""
    <footer class="px-4 pb-8 text-center text-xs text-gray-400">
      <span>xDoor</span>
      <span class="mx-1">·</span>
      <%= if @href do %>
        <a
          id="app-version"
          href={@href}
          target="_blank"
          rel="noopener noreferrer"
          class="font-mono transition-colors hover:text-gray-600 hover:underline"
        >
          v{@version}
        </a>
      <% else %>
        <span id="app-version" class="font-mono">v{@version}</span>
      <% end %>
    </footer>
    """
  end

  # Tagged builds link to their release, untagged builds to their commit.
  defp version_url(version) do
    case Version.parse(version) do
      {:ok, %Version{pre: [], build: nil}} ->
        "#{@repo_url}/releases/tag/v#{version}"

      {:ok, %Version{build: build}} when is_binary(build) ->
        case Regex.run(~r/(?:^|\.)g([0-9a-f]+)/, build) do
          [_, sha] -> "#{@repo_url}/commit/#{sha}"
          nil -> nil
        end

      _ ->
        nil
    end
  end
end
