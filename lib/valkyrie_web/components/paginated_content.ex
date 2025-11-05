defmodule ValkyrieWeb.Components.PaginatedContent do
  use Phoenix.Component
  import ValkyrieWeb.Components.Pagination
  import ValkyrieWeb.Components.SearchField

  attr :search_query, :string, default: "", doc: "Search query"
  attr :search_placeholder, :string, default: "Search...", doc: "Search placeholder"
  attr :page, :map, default: nil, doc: "Ash.Offset page object"

  slot :inner_block, required: true, doc: "Inner block that renders HEEx content"

  def paginated_content(assigns) do
    # Calculate current page and total pages from the Ash.Offset object
    {current_page, total_pages} =
      if assigns.page do
        current_page = div(assigns.page.offset, assigns.page.limit) + 1
        total_pages = div(assigns.page.count, assigns.page.limit)
        {current_page, total_pages}
      else
        {1, 1}
      end

    assigns = assign(assigns, :current_page, current_page)
    assigns = assign(assigns, :total_pages, total_pages)

    ~H"""
    <div class="mb-6">
      <.form for={} phx-change="search" phx-debounce="500">
        <.search_field
          id="member-search"
          name="search_query"
          value={@search_query}
          placeholder={@search_placeholder}
        />
      </.form>
    </div>

    {render_slot(@inner_block)}

    <div class="mt-8 flex justify-center">
      <.pagination
        id="pagination"
        rounded="large"
        variant="transparent"
        total={@total_pages}
        active={@current_page}
      />
    </div>
    """
  end
end
