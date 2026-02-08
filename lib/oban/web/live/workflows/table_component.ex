defmodule Oban.Web.Workflows.TableComponent do
  use Oban.Web, :live_component

  @inc_limit 20
  @max_limit 200
  @min_limit 20

  @impl Phoenix.LiveComponent
  def update(assigns, socket) do
    socket =
      socket
      |> assign(params: assigns.params, workflows: assigns.workflows)
      |> assign(show_less?: assigns.params.limit > @min_limit)
      |> assign(show_more?: assigns.params.limit < @max_limit)

    {:ok, socket}
  end

  @impl Phoenix.LiveComponent
  def render(assigns) do
    ~H"""
    <div id="workflows-table" class="min-w-full">
      <ul class="flex items-center border-b border-gray-200 dark:border-gray-700 text-gray-400 dark:text-gray-600">
        <.col_header label="name" class="ml-12 w-1/4 text-left" />
        <div class="ml-auto flex items-center space-x-6">
          <.col_header label="workflow id" class="w-44 text-left" />
          <.col_header label="jobs" class="w-16 text-right" />
          <.col_header label="state" class="w-24 text-center" />
          <.col_header label="time" class="w-28 pr-3 text-right" />
        </div>
      </ul>

      <div
        :if={Enum.empty?(@workflows)}
        class="flex items-center justify-center py-12 space-x-2 text-lg text-gray-600 dark:text-gray-300"
      >
        <Icons.no_symbol /> <span>No workflows match the current set of filters.</span>
      </div>

      <ul class="divide-y divide-gray-100 dark:divide-gray-800">
        <.workflow_row :for={workflow <- @workflows} workflow={workflow} />
      </ul>

      <div class="py-6 flex items-center justify-center space-x-6">
        <.load_button label="Show Less" click="load-less" active={@show_less?} myself={@myself} />
        <.load_button label="Show More" click="load-more" active={@show_more?} myself={@myself} />
      </div>
    </div>
    """
  end

  attr :label, :string, required: true
  attr :class, :string, default: ""

  defp col_header(assigns) do
    ~H"""
    <span class={[@class, "text-xs font-medium uppercase tracking-wider py-1.5 pl-4"]}>
      {@label}
    </span>
    """
  end

  attr :workflow, :map, required: true

  defp workflow_row(assigns) do
    ~H"""
    <li
      id={"workflow-#{@workflow.id}"}
      class="flex items-center hover:bg-gray-50 dark:hover:bg-gray-950/30"
    >
      <.link
        patch={oban_path([:workflows, @workflow.id])}
        class="py-5 pl-12 flex flex-grow items-center"
      >
        <div rel="name" class="w-1/4 font-semibold text-gray-700 dark:text-gray-300 truncate">
          {@workflow.name || "Unnamed"}
        </div>

        <div class="ml-auto flex items-center space-x-6 text-gray-500 dark:text-gray-300">
          <span
            rel="workflow-id"
            class="w-44 text-left font-mono text-sm truncate"
            title={@workflow.id}
          >
            {truncate(@workflow.id, 0..20)}
          </span>

          <span rel="total" class="w-16 text-right tabular">
            {integer_to_estimate(@workflow.total_jobs)}
          </span>

          <span
            rel="state"
            class={[
              "w-24 text-center text-xs font-medium rounded-full px-2 py-0.5",
              state_class(@workflow.state)
            ]}
          >
            {@workflow.state}
          </span>

          <div
            class="w-28 pr-3 text-sm text-right tabular"
            data-timestamp={timestamp(@workflow)}
            data-relative-mode={relative_mode(@workflow)}
            id={"workflow-ts-#{@workflow.id}"}
            phx-hook="Relativize"
            phx-update="ignore"
          >
            00:00
          </div>
        </div>
      </.link>
    </li>
    """
  end

  defp load_button(assigns) do
    ~H"""
    <button
      type="button"
      class={"font-semibold text-sm focus:outline-none focus:ring-1 focus:ring-blue-500 focus:border-blue-500 #{loader_class(@active)}"}
      phx-target={@myself}
      phx-click={@click}
    >
      {@label}
    </button>
    """
  end

  @impl Phoenix.LiveComponent
  def handle_event("load-less", _params, socket) do
    if socket.assigns.show_less? do
      send(self(), {:params, :limit, -@inc_limit})
    end

    {:noreply, socket}
  end

  def handle_event("load-more", _params, socket) do
    if socket.assigns.show_more? do
      send(self(), {:params, :limit, @inc_limit})
    end

    {:noreply, socket}
  end

  defp state_class("executing"),
    do: "bg-blue-100 text-blue-800 dark:bg-blue-900 dark:text-blue-200"

  defp state_class("completed"),
    do: "bg-green-100 text-green-800 dark:bg-green-900 dark:text-green-200"

  defp state_class("available"),
    do: "bg-yellow-100 text-yellow-800 dark:bg-yellow-900 dark:text-yellow-200"

  defp state_class("retryable"),
    do: "bg-orange-100 text-orange-800 dark:bg-orange-900 dark:text-orange-200"

  defp state_class("cancelled"),
    do: "bg-gray-100 text-gray-800 dark:bg-gray-700 dark:text-gray-200"

  defp state_class("discarded"), do: "bg-red-100 text-red-800 dark:bg-red-900 dark:text-red-200"
  defp state_class(_state), do: "bg-gray-100 text-gray-800 dark:bg-gray-700 dark:text-gray-200"

  defp timestamp(%{started_at: nil}), do: "-"

  defp timestamp(%{started_at: started_at}) do
    DateTime.to_unix(started_at, :millisecond)
  end

  defp relative_mode(%{state: "executing"}), do: "duration"
  defp relative_mode(_workflow), do: "words"

  defp loader_class(true) do
    """
    text-gray-700 dark:text-gray-300 cursor-pointer transition ease-in-out duration-200 border-b
    border-gray-200 dark:border-gray-800 hover:border-gray-400
    """
  end

  defp loader_class(_), do: "text-gray-400 dark:text-gray-600 cursor-not-allowed"
end
