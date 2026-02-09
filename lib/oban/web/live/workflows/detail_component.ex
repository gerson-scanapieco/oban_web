defmodule Oban.Web.Workflows.DetailComponent do
  use Oban.Web, :live_component

  alias Oban.Web.{Resolver, Timing}
  alias Oban.Web.Workflows.TimelineComponent

  @inc_limit 20
  @max_limit 200
  @min_limit 20

  @impl Phoenix.LiveComponent
  def update(assigns, socket) do
    socket =
      socket
      |> assign(assigns)
      |> assign_new(:graph_open?, fn -> true end)
      |> assign(show_less?: assigns.params.limit > @min_limit)
      |> assign(show_more?: assigns.params.limit < @max_limit)

    {:ok, socket}
  end

  @impl Phoenix.LiveComponent
  def render(assigns) do
    ~H"""
    <div id="workflow-details">
      <div class="flex justify-between items-center px-3 py-4 border-b border-gray-200 dark:border-gray-700">
        <button
          id="back-link"
          class="flex items-center hover:text-blue-500 cursor-pointer bg-transparent border-0 p-0"
          data-title="Back to workflows"
          phx-hook="HistoryBack"
          type="button"
        >
          <Icons.arrow_left class="w-5 h-5" />
          <span class="text-lg font-bold ml-2">Workflow Details</span>
        </button>
      </div>

      <div class="bg-blue-50 dark:bg-blue-950 dark:bg-opacity-25 border-b border-gray-200 dark:border-gray-700 px-3 py-6">
        <div class="flex justify-between items-center">
          <div>
            <span class="text-md font-mono text-gray-500 dark:text-gray-400 tabular">
              {truncate(@workflow.id, 0..20)}
            </span>
            <span class="text-lg font-bold text-gray-900 dark:text-gray-200 ml-1">
              {@workflow.name || "Unnamed"}
            </span>
          </div>
        </div>

        <div class="text-sm flex justify-left pt-2 text-gray-900 dark:text-gray-200">
          <div class="mr-6">
            <span class="uppercase font-semibold text-xs text-gray-500 dark:text-gray-400 mr-1">
              Total Jobs
            </span>
            {integer_to_delimited(@workflow.total_jobs)}
          </div>
          <div class="mr-6">
            <span class="uppercase font-semibold text-xs text-gray-500 dark:text-gray-400 mr-1">
              Queue Time
            </span>
            <span class="tabular">{wf_queue_time(@workflow)}</span>
          </div>
          <div class="mr-6">
            <span class="uppercase font-semibold text-xs text-gray-500 dark:text-gray-400 mr-1">
              Run Time
            </span>
            <span class="tabular">{wf_run_time(@workflow, @os_time)}</span>
          </div>
        </div>
      </div>

      <div class="flex justify-center items-center px-3 pt-6 pb-5 border-b border-gray-200 dark:border-gray-700">
        <TimelineComponent.render workflow={@workflow} os_time={@os_time} state="inserted" />
        <TimelineComponent.render workflow={@workflow} os_time={@os_time} state="scheduled" />
        <TimelineComponent.render workflow={@workflow} os_time={@os_time} state="executing" />
        <TimelineComponent.render workflow={@workflow} os_time={@os_time} state="cancelled" />
        <TimelineComponent.render workflow={@workflow} os_time={@os_time} state="discarded" />
      </div>

      <div :if={@graph_nodes != []} class="border-b border-gray-200 dark:border-gray-700">
        <button
          type="button"
          class="flex items-center w-full px-3 py-2 text-xs font-medium uppercase tracking-wider text-gray-400 dark:text-gray-600 hover:text-gray-600 dark:hover:text-gray-400 cursor-pointer"
          phx-click="toggle-graph"
          phx-target={@myself}
        >
          <Icons.chevron_down :if={@graph_open?} class="w-4 h-4 mr-1" />
          <Icons.chevron_right :if={!@graph_open?} class="w-4 h-4 mr-1" /> Graph
        </button>

        <div
          :if={@graph_open?}
          id="workflow-graph"
          phx-hook="WorkflowGraph"
          data-graph={Jason.encode!(@graph_nodes)}
          data-job-path-prefix={oban_path(:jobs)}
          class="overflow-hidden"
          style="height: 300px;"
        >
        </div>
      </div>

      <ul class="flex items-center border-b border-gray-200 dark:border-gray-700 text-gray-400 dark:text-gray-600">
        <.header label="details" class="ml-6" />
        <.header label="queue" class="ml-auto text-right" />
        <.header label="time" class="w-20 pr-3 text-right" />
      </ul>

      <div :if={Enum.empty?(@jobs)} class="text-lg text-center py-12">
        <div class="flex items-center justify-center space-x-2 text-gray-600 dark:text-gray-300">
          <Icons.no_symbol /> <span>No jobs match the current set of filters.</span>
        </div>
      </div>

      <ul class="divide-y divide-gray-100 dark:divide-gray-800">
        <.job_row :for={job <- @jobs} job={job} resolver={@resolver} />
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

  defp header(assigns) do
    ~H"""
    <span class={[@class, "text-xs font-medium uppercase tracking-wider py-1.5 pl-4"]}>
      {@label}
    </span>
    """
  end

  attr :job, :map, required: true
  attr :resolver, :any, required: true

  defp job_row(assigns) do
    ~H"""
    <li id={"wf-job-#{@job.id}"} class="flex items-center hover:bg-gray-50 dark:hover:bg-gray-950/30">
      <.link patch={oban_path([:jobs, @job.id])} class="pl-6 flex flex-grow items-center">
        <div class="py-2.5">
          <span class="block font-semibold text-sm text-gray-700 dark:text-gray-300" rel="worker">
            {@job.worker}
          </span>

          <span class="tabular text-xs text-gray-600 dark:text-gray-300" rel="attempts">
            {@job.attempt} ⁄ {@job.max_attempts}
          </span>

          <samp class="ml-2 font-mono truncate text-xs text-gray-500 dark:text-gray-400" rel="args">
            {format_args(@job, @resolver)}
          </samp>
        </div>

        <div class="ml-auto flex items-center space-x-1">
          <span class="py-1.5 px-2 tabular truncate text-xs rounded-md bg-gray-100 dark:bg-gray-950">
            {@job.queue}
          </span>
        </div>

        <div
          class="w-20 pr-3 text-sm text-right tabular text-gray-500 dark:text-gray-300"
          data-timestamp={timestamp(@job)}
          data-relative-mode={relative_mode(@job)}
          id={"wf-job-ts-#{@job.id}"}
          phx-hook="Relativize"
          phx-update="ignore"
        >
          00:00
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
  def handle_event("toggle-graph", _params, socket) do
    {:noreply, assign(socket, graph_open?: !socket.assigns.graph_open?)}
  end

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

  # Helpers

  defp format_args(job, resolver) do
    resolver
    |> Resolver.call_with_fallback(:format_job_args, [job])
    |> truncate(0..98)
  end

  defp wf_queue_time(workflow), do: Timing.queue_time(workflow)

  @empty_time "-"

  defp wf_run_time(%{attempted_at: nil}, _os_time), do: @empty_time

  defp wf_run_time(workflow, os_time) do
    finished_at =
      case workflow.state do
        "completed" -> workflow.completed_at
        "cancelled" -> workflow.cancelled_at
        "discarded" -> workflow.discarded_at
        _ -> DateTime.from_unix!(os_time)
      end

    if finished_at do
      workflow.attempted_at
      |> DateTime.diff(finished_at, :millisecond)
      |> Timing.to_duration(:millisecond)
    else
      @empty_time
    end
  end

  defp timestamp(job) do
    datetime =
      case job.state do
        "available" -> job.scheduled_at
        "cancelled" -> job.cancelled_at
        "completed" -> job.completed_at
        "discarded" -> job.discarded_at
        "executing" -> job.attempted_at
        "retryable" -> job.scheduled_at
        "scheduled" -> job.scheduled_at
      end

    if is_struct(datetime) do
      DateTime.to_unix(datetime, :millisecond)
    else
      "-"
    end
  end

  defp relative_mode(job) do
    if job.state == "executing", do: "duration", else: "words"
  end

  defp loader_class(true) do
    """
    text-gray-700 dark:text-gray-300 cursor-pointer transition ease-in-out duration-200 border-b
    border-gray-200 dark:border-gray-800 hover:border-gray-400
    """
  end

  defp loader_class(_), do: "text-gray-400 dark:text-gray-600 cursor-not-allowed"
end
