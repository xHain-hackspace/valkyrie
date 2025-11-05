defmodule ValkyrieWeb.PaginationHelpers do
  @moduledoc """
  Shared pagination event handlers for LiveViews.
  """

  defmacro __using__(opts) do
    update_function = Keyword.get(opts, :update_function, :update_list)

    quote do
      @impl true
      def handle_event("search", %{"search_query" => search_query}, socket) do
        socket = socket |> assign(:search_query, search_query)
        {:noreply, apply(__MODULE__, unquote(update_function), [socket])}
      end

      @impl true
      def handle_event("pagination", params, socket) do
        socket = socket |> set_offset(params)
        {:noreply, apply(__MODULE__, unquote(update_function), [socket])}
      end

      defp set_offset(socket, %{"action" => "select", "page" => selected_page}) do
        desired_offset = get_offset_for_page(socket, selected_page)
        assign(socket, :page, %{socket.assigns.page | offset: desired_offset})
      end

      defp set_offset(socket, %{"action" => "first"}) do
        assign(socket, :page, %{socket.assigns.page | offset: get_offset_for_page(socket, 1)})
      end

      defp set_offset(socket, %{"action" => "last"}) do
        {limit, _offset, count} = get_offset_params(socket)
        desired_offset = (div(count, limit) - 1) * limit
        assign(socket, :page, %{socket.assigns.page | offset: desired_offset})
      end

      defp set_offset(socket, %{"action" => "next"}) do
        {limit, offset, _count} = get_offset_params(socket)
        desired_offset = offset + limit
        assign(socket, :page, %{socket.assigns.page | offset: desired_offset})
      end

      defp set_offset(socket, %{"action" => "previous"}) do
        {limit, offset, _count} = get_offset_params(socket)
        desired_offset = offset - limit
        assign(socket, :page, %{socket.assigns.page | offset: desired_offset})
      end

      defp get_offset_for_page(socket, selected_page) do
        {limit, offset, count} = get_offset_params(socket)

        desired_offset = (selected_page - 1) * limit
        max(desired_offset, 0) |> min(count)
      end

      defp get_offset_params(socket) do
        if socket.assigns.page do
          {socket.assigns.page.limit, socket.assigns.page.offset, socket.assigns.page.count}
        else
          {20, 0, 0}
        end
      end
    end
  end
end
