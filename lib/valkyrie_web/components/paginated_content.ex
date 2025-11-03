defmodule ValkyrieWeb.Components.PaginatedContent do
  use Phoenix.Component
  import ValkyrieWeb.Components.Pagination
  import ValkyrieWeb.Components.SearchField

  attr :search_query, :string, default: "", doc: "Search query"
  attr :pagination, :map, required: true, doc: "Pagination"

  slot :inner_block, required: true, doc: "Inner block that renders HEEx content"

  def paginated_content(assigns) do
    ~H"""
    <div class="mb-6">
      <.form for={} phx-change="search" phx-debounce="500">
        <.search_field
          id="member-search"
          name="search_query"
          value={@search_query}
          placeholder="Search by username..."
        />
      </.form>
    </div>

    {render_slot(@inner_block)}

    <div class="mt-8 flex justify-center">
      <.pagination
        id="pagination"
        rounded="large"
        variant="transparent"
        total={@pagination.total}
        active={@pagination.page}
      />
    </div>
    """
  end
end
