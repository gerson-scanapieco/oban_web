defmodule Oban.Web.WorkflowsPage do
  @behaviour Oban.Web.Page

  use Oban.Web, :live_component

  alias Oban.Web.Workflows.{
    DetailComponent,
    DetailSidebarComponent,
    SidebarComponent,
    TableComponent
  }

  alias Oban.Web.{Page, SearchComponent, SortComponent, WorkflowQuery}

  @known_params ~w(ids names nodes queues sort_by sort_dir states limit)

  @impl Phoenix.LiveComponent
  def render(assigns) do
    ~H"""
    <div id="workflows-page" class="w-full flex flex-col my-6 md:flex-row">
      <%= if @detailed do %>
        <DetailSidebarComponent.sidebar
          workflow_id={@detailed.id}
          params={without_defaults(@params, @default_params)}
          states={@filter_states}
          queues={@filter_queues}
          nodes={@filter_nodes}
          width={@sidebar_width}
          csp_nonces={@csp_nonces}
        />

        <div class="grow">
          <div class="bg-white dark:bg-gray-900 rounded-md shadow-lg">
            <.live_component
              id="workflow-detail"
              module={DetailComponent}
              workflow={@detailed}
              jobs={@jobs}
              graph_nodes={@graph_nodes}
              params={@params}
              resolver={@resolver}
              os_time={@os_time}
            />
          </div>
        </div>
      <% else %>
        <SidebarComponent.sidebar
          state_counts={@state_counts}
          params={without_defaults(@params, @default_params)}
          active_states={@params[:states]}
          width={@sidebar_width}
          csp_nonces={@csp_nonces}
        />

        <div class="grow">
          <div class="bg-white dark:bg-gray-900 rounded-md shadow-lg">
            <div class="flex items-start pr-3 py-3 border-b border-gray-200 dark:border-gray-700">
              <div id="workflows-header" class="h-10 pr-12 flex-none flex items-center">
                <div class="flex-none flex items-center pl-12">
                  <h2 class="text-lg dark:text-gray-200 leading-4 font-bold">Workflows</h2>
                </div>
              </div>

              <.live_component
                conf={@conf}
                id="search"
                module={SearchComponent}
                page={:workflows}
                params={without_defaults(@params, @default_params)}
                queryable={WorkflowQuery}
                resolver={@resolver}
              />

              <div class="pl-3 ml-auto">
                <SortComponent.select
                  id="workflows-sort"
                  by={~w(time name total)}
                  page={:workflows}
                  params={@params}
                />
              </div>
            </div>

            <.live_component
              id="workflows-table"
              module={TableComponent}
              params={@params}
              workflows={@workflows}
            />
          </div>
        </div>
      <% end %>
    </div>
    """
  end

  @keep_on_mount ~w(default_params detailed filter_nodes filter_queues filter_states graph_nodes jobs os_time params state_counts workflows)a

  @impl Page
  def handle_mount(socket) do
    default = fn -> %{limit: 20, sort_by: "time", sort_dir: "desc", states: ["executing"]} end

    assigns =
      Map.drop(socket.assigns, @keep_on_mount)

    %{socket | assigns: assigns}
    |> assign_new(:default_params, default)
    |> assign_new(:detailed, fn -> nil end)
    |> assign_new(:filter_nodes, fn -> [] end)
    |> assign_new(:filter_queues, fn -> [] end)
    |> assign_new(:filter_states, fn -> [] end)
    |> assign_new(:graph_nodes, fn -> [] end)
    |> assign_new(:jobs, fn -> [] end)
    |> assign_new(:os_time, fn -> System.os_time(:second) end)
    |> assign_new(:params, default)
    |> assign_new(:state_counts, fn -> %{} end)
    |> assign_new(:workflows, fn -> [] end)
  end

  @impl Page
  def handle_refresh(socket) do
    if socket.assigns.detailed do
      refresh_detail(socket)
    else
      refresh_list(socket)
    end
  end

  defp refresh_list(socket) do
    conf = socket.assigns.conf
    params = socket.assigns.params

    all_workflows = WorkflowQuery.all_workflows(params, conf)
    state_counts = Enum.frequencies_by(all_workflows, & &1.state)
    workflows = filter_by_states(all_workflows, params)

    assign(socket, workflows: workflows, state_counts: state_counts)
  end

  defp refresh_detail(socket) do
    %{conf: conf, params: params, detailed: detailed} = socket.assigns

    case WorkflowQuery.get_workflow(conf, detailed.id) do
      nil ->
        push_patch(socket, to: oban_path(:workflows), replace: true)

      workflow ->
        jobs = WorkflowQuery.workflow_jobs(params, conf, workflow.id)
        filters = WorkflowQuery.workflow_job_filters(conf, workflow.id)
        graph_nodes = WorkflowQuery.workflow_graph(conf, workflow.id)

        assign(socket,
          detailed: workflow,
          jobs: jobs,
          graph_nodes: graph_nodes,
          os_time: System.os_time(:second),
          filter_states: filters.states,
          filter_queues: filters.queues,
          filter_nodes: filters.nodes
        )
    end
  end

  defp filter_by_states(workflows, %{states: states}) when is_list(states) and states != [] do
    Enum.filter(workflows, &(&1.state in states))
  end

  defp filter_by_states(workflows, _params), do: workflows

  @impl Page
  def handle_params(%{"id" => workflow_id} = params, _uri, socket) do
    params =
      params
      |> Map.take(@known_params)
      |> decode_params()

    conf = socket.assigns.conf

    case WorkflowQuery.get_workflow(conf, workflow_id) do
      nil ->
        {:noreply, push_patch(socket, to: oban_path(:workflows), replace: true)}

      workflow ->
        detail_defaults = Map.delete(socket.assigns.default_params, :states)
        params = Map.merge(detail_defaults, params)
        jobs = WorkflowQuery.workflow_jobs(params, conf, workflow.id)
        filters = WorkflowQuery.workflow_job_filters(conf, workflow.id)
        graph_nodes = WorkflowQuery.workflow_graph(conf, workflow.id)

        socket =
          socket
          |> assign(page_title: page_title("Workflow"))
          |> assign(
            detailed: workflow,
            jobs: jobs,
            graph_nodes: graph_nodes,
            os_time: System.os_time(:second),
            params: params,
            filter_states: filters.states,
            filter_queues: filters.queues,
            filter_nodes: filters.nodes
          )

        {:noreply, socket}
    end
  end

  def handle_params(params, _uri, socket) do
    params =
      params
      |> Map.take(@known_params)
      |> decode_params()

    socket =
      socket
      |> assign(page_title: page_title("Workflows"))
      |> assign(
        detailed: nil,
        graph_nodes: [],
        jobs: [],
        filter_states: [],
        filter_queues: [],
        filter_nodes: []
      )
      |> assign(params: Map.merge(socket.assigns.default_params, params))
      |> handle_refresh()

    {:noreply, socket}
  end

  @impl Page
  def handle_info({:params, :limit, inc}, socket) when is_integer(inc) do
    params =
      socket.assigns.params
      |> Map.update!(:limit, &to_string(&1 + inc))
      |> without_defaults(socket.assigns.default_params)

    path =
      if socket.assigns.detailed do
        oban_path([:workflows, socket.assigns.detailed.id], params)
      else
        oban_path(:workflows, params)
      end

    {:noreply, push_patch(socket, to: path, replace: true)}
  end

  def handle_info(_, socket) do
    {:noreply, socket}
  end
end
